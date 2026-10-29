using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ChaoWenSetup
{
    public class InstallerForm : Form
    {
        private readonly Label _status;
        private readonly ProgressBar _bar;
        private readonly Button _button;

        public InstallerForm()
        {
            Text = "朝闻 · 安装";
            ClientSize = new Size(460, 210);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            BackColor = Color.FromArgb(251, 250, 247);

            var title = new Label();
            title.Text = "朝闻";
            title.Font = new Font("Microsoft YaHei", 22F, FontStyle.Bold);
            title.ForeColor = Color.FromArgb(200, 16, 46);
            title.AutoSize = true;
            title.Location = new Point(28, 22);
            Controls.Add(title);

            var sub = new Label();
            sub.Text = "人民日报阅报器 · 安装到当前用户";
            sub.Font = new Font("Microsoft YaHei", 9F);
            sub.ForeColor = Color.FromArgb(110, 106, 99);
            sub.AutoSize = true;
            sub.Location = new Point(32, 68);
            Controls.Add(sub);

            _status = new Label();
            _status.Text = "准备安装…";
            _status.Font = new Font("Microsoft YaHei", 9F);
            _status.ForeColor = Color.FromArgb(60, 58, 55);
            _status.AutoSize = false;
            _status.Size = new Size(400, 22);
            _status.Location = new Point(32, 108);
            Controls.Add(_status);

            _bar = new ProgressBar();
            _bar.Location = new Point(32, 132);
            _bar.Size = new Size(396, 10);
            _bar.Style = ProgressBarStyle.Continuous;
            Controls.Add(_bar);

            _button = new Button();
            _button.Text = "开始安装";
            _button.Font = new Font("Microsoft YaHei", 9F);
            _button.Size = new Size(120, 36);
            _button.Location = new Point(308, 156);
            _button.BackColor = Color.FromArgb(200, 16, 46);
            _button.ForeColor = Color.White;
            _button.FlatStyle = FlatStyle.Flat;
            _button.FlatAppearance.BorderSize = 0;
            _button.Click += OnInstall;
            Controls.Add(_button);
        }

        private string TargetDir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs\\ChaoWen"); }
        }

        private void OnInstall(object sender, EventArgs e)
        {
            _button.Enabled = false;
            var worker = new BackgroundWorker();
            worker.DoWork += delegate { Install(); };
            worker.RunWorkerCompleted += OnDone;
            worker.RunWorkerAsync();
        }

        private void Install()
        {
            var temp = Path.Combine(Path.GetTempPath(), "chaowen_setup");
            if (Directory.Exists(temp)) Directory.Delete(temp, true);
            Directory.CreateDirectory(temp);

            SetStatus("正在解压…");
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (stream == null) throw new Exception("安装包损坏：找不到 payload");
                var zipPath = Path.Combine(temp, "payload.zip");
                using (var file = File.Create(zipPath)) stream.CopyTo(file);
                ZipFile.ExtractToDirectory(zipPath, temp);
                File.Delete(zipPath);
            }

            SetStatus("正在复制文件…");
            if (Directory.Exists(TargetDir))
            {
                foreach (var p in Process.GetProcessesByName("rmrb_reader"))
                {
                    try { p.Kill(); } catch { }
                }
                System.Threading.Thread.Sleep(600);
            }
            CopyDirectory(temp, TargetDir);
            try { Directory.Delete(temp, true); } catch { }

            SetStatus("正在创建快捷方式…");
            CreateShortcuts();
            WriteUninstallEntry();
            _progress = 100;
        }

        private int _progress;

        private void SetStatus(string text)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(delegate { SetStatus(text); }));
                return;
            }
            _status.Text = text;
            _progress = Math.Min(95, _progress + 25);
            _bar.Value = _progress;
        }

        private static void CopyDirectory(string source, string target)
        {
            Directory.CreateDirectory(target);
            foreach (var dir in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
            {
                Directory.CreateDirectory(dir.Replace(source, target));
            }
            foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
            {
                File.Copy(file, file.Replace(source, target), true);
            }
        }

        private void CreateShortcuts()
        {
            var exe = Path.Combine(TargetDir, "rmrb_reader.exe");
            var shellType = Type.GetTypeFromProgID("WScript.Shell");
            var shell = Activator.CreateInstance(shellType);
            var targets = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "朝闻.lnk"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "朝闻.lnk")
            };
            foreach (var lnk in targets)
            {
                var shortcut = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
                var t = shortcut.GetType();
                t.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { exe });
                t.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { TargetDir });
                t.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { exe + ",0" });
                t.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { "人民日报阅报器" });
                t.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
            }
        }

        private void WriteUninstallEntry()
        {
            var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\ChaoWen");
            if (key == null) return;
            key.SetValue("DisplayName", "朝闻 · 人民日报阅报器");
            key.SetValue("DisplayVersion", "0.1.0");
            key.SetValue("Publisher", "个人项目");
            key.SetValue("DisplayIcon", Path.Combine(TargetDir, "rmrb_reader.exe"));
            key.SetValue("InstallLocation", TargetDir);
            key.SetValue("UninstallString", Path.Combine(TargetDir, "uninstall.cmd"));
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            key.Close();
        }

        private void OnDone(object sender, RunWorkerCompletedEventArgs e)
        {
            if (e.Error != null)
            {
                _status.Text = "安装失败：" + e.Error.Message;
                _button.Enabled = true;
                _button.Text = "重试";
                return;
            }
            _bar.Value = 100;
            _status.Text = "安装完成，正在启动…";
            try
            {
                Process.Start(new ProcessStartInfo(Path.Combine(TargetDir, "rmrb_reader.exe")) { WorkingDirectory = TargetDir });
            }
            catch { }
            var timer = new Timer();
            timer.Interval = 1200;
            timer.Tick += delegate { timer.Stop(); Close(); };
            timer.Start();
        }

        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
        }
    }
}
