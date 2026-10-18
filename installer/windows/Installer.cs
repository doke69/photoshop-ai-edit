using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

internal static class Installer {
    static Window window;
    static string work;
    static bool busy, uninstall, success, preview;
    static string diagnostic = "";
    static T Find<T>(string name) where T : class { return window.FindName(name) as T; }
    static Stream Resource(string name) { return Assembly.GetExecutingAssembly().GetManifestResourceStream(name); }
    [STAThread] public static int Main(string[] args) {
        try {
            // Preview mode cannot invoke installation, open guides or access Adobe data.
            preview = args.Length > 0;
            if (preview && (args.Length != 2 || args[0] != "--preview")) throw new ArgumentException("Usage: --preview output.png");
            var app = new Application();
            using (var stream = Resource("Main.xaml")) window = (Window)XamlReader.Load(stream);
            using (var stream = Resource("Brand.png")) {
                var logo = new BitmapImage(); logo.BeginInit(); logo.StreamSource = stream;
                logo.CacheOption = BitmapCacheOption.OnLoad; logo.EndInit(); logo.Freeze();
                Find<Image>("BrandImage").Source = logo; window.Icon = logo;
            }
            Find<TextBlock>("VersionLabel").Text = "●  Windows · v" + Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
            foreach (var name in new[] { "InstallTab", "UninstallTab", "Primary", "Guide", "SaveLog" })
                System.Windows.Automation.AutomationProperties.SetAutomationId(Find<Button>(name), name);
            var area = SystemParameters.WorkArea;
            window.Width = Math.Min(window.Width, area.Width); window.Height = Math.Min(window.Height, area.Height);
            window.MinWidth = Math.Min(window.MinWidth, area.Width); window.MinHeight = Math.Min(window.MinHeight, area.Height);
            Find<Button>("InstallTab").Click += delegate { SetMode(false); };
            Find<Button>("UninstallTab").Click += delegate { SetMode(true); };
            Find<Button>("Primary").Click += async delegate { if (!preview) { if (success) OpenGuide(); else await Run(); } };
            Find<Button>("Guide").Click += delegate { if (!preview) OpenGuide(); };
            Find<Button>("SaveLog").Click += delegate { if (!preview) SaveLog(); };
            window.Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e) { if (busy) e.Cancel = true; };
            SetMode(false);
            if (preview) {
                window.ContentRendered += delegate {
                    var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
                    timer.Tick += delegate {
                        timer.Stop();
                        try {
                            var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
                            bitmap.Render(window); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                            using (var output = File.Create(Path.GetFullPath(args[1]))) encoder.Save(output);
                        } finally { window.Close(); }
                    }; timer.Start();
                };
            }
            app.Run(window); return 0;
        } catch (Exception e) { MessageBox.Show(e.Message, "Photoshop AI Edit", MessageBoxButton.OK, MessageBoxImage.Error); return 1; }
        finally { if (work != null) try { Directory.Delete(work, true); } catch { } }
    }
    static void SetMode(bool remove) {
        if (busy) return;
        uninstall = remove; success = false;
        Find<Button>("InstallTab").Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(remove ? "#171D24" : "#343C47"));
        Find<Button>("UninstallTab").Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(remove ? "#343C47" : "#171D24"));
        Find<TextBlock>("Heading").Text = remove ? "移除插件，保留你的数据。" : "把 AI 带进你的工作流。";
        Find<TextBlock>("Subtitle").Text = remove ? "仅移除本插件，其他插件和私有数据保持不变。" : "安装到当前用户，无需管理员权限或开发工具。";
        Find<TextBlock>("StepTwo").Text = remove ? "02   备份文件，移除插件登记" : "02   一键安装，保留你的数据";
        Find<Button>("Primary").Content = remove ? "卸载插件（保留数据）" : "安装 AI 局部改图  →";
        Find<StackPanel>("Steps").Visibility = Visibility.Visible;
        Find<ScrollViewer>("ResultPanel").Visibility = Visibility.Collapsed;
    }
    static void Prepare() {
        if (preview) throw new InvalidOperationException("Preview mode is read-only.");
        if (work != null) return;
        var destination = Path.Combine(Path.GetTempPath(), "Photoshop-AI-Edit-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(destination);
        try {
        using (var stream = Resource("Payload.zip"))
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Read)) {
            foreach (var entry in archive.Entries) {
                var target = Path.GetFullPath(Path.Combine(destination, entry.FullName));
                if (!target.StartsWith(destination + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new IOException("Invalid payload path.");
                if (entry.Name.Length == 0) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                using (var input = entry.Open()) using (var output = File.Create(target)) input.CopyTo(output);
            }
        }
        work = destination;
        } catch { try { Directory.Delete(destination, true); } catch { } throw; }
    }
    static async Task Run() {
        busy = true;
        foreach (var name in new[] { "InstallTab", "UninstallTab", "Primary", "Guide" }) Find<Button>(name).IsEnabled = false;
        Find<ProgressBar>("Progress").Visibility = Visibility.Visible;
        Find<Button>("Primary").Content = uninstall ? "正在卸载…" : "正在安装…";
        ShowResult(uninstall ? "正在卸载…" : "正在安装…", "正在备份并更新插件文件和登记，请稍候。", false);
        try {
            var report = await Task.Run(delegate {
                if (Process.GetProcessesByName("Photoshop").Length > 0) throw new InvalidOperationException("请先保存文件并完全退出 Photoshop，再重试。");
                Prepare();
                var start = new ProcessStartInfo {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"),
                    Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + Path.Combine(work, "install.ps1") + "\" -NoGuide" + (uninstall ? " -Uninstall" : ""),
                    UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = work
                };
                using (var process = Process.Start(start)) {
                    var stdout = process.StandardOutput.ReadToEndAsync(); var stderr = process.StandardError.ReadToEndAsync();
                    process.WaitForExit(); Task.WaitAll(stdout, stderr);
                    var text = stdout.Result + "\n" + stderr.Result;
                    if (process.ExitCode != 0) throw new InvalidOperationException(text.Trim());
                    return text;
                }
            });
            diagnostic = "Action: " + (uninstall ? "Uninstall" : "Install") + "\n" + report;
            success = true;
            ShowResult(uninstall ? "卸载完成" : "安装完成", uninstall ? "本插件已移除，Key 和任务历史已保留。下次启动 Photoshop 后生效。" : "重新打开 Photoshop，在「增效工具 → AI 局部改图」中启动。接下来按使用指南创建并设置 API Key。", false);
        } catch (Exception e) {
            diagnostic = "Action: " + (uninstall ? "Uninstall" : "Install") + "\n" + e.Message;
            ShowResult("操作未完成", "请确认 Photoshop 已退出、当前用户目录可写。你可以保存诊断记录协助排查。\n\n" + e.Message, true);
        } finally {
            busy = false;
            foreach (var name in new[] { "InstallTab", "UninstallTab", "Primary", "Guide" }) Find<Button>(name).IsEnabled = true;
            Find<ProgressBar>("Progress").Visibility = Visibility.Collapsed;
            Find<Button>("Primary").Content = success ? "查看 API 设置与使用指南  ↗" : "重试";
        }
    }
    static void ShowResult(string title, string body, bool error) {
        Find<StackPanel>("Steps").Visibility = Visibility.Collapsed;
        Find<ScrollViewer>("ResultPanel").Visibility = Visibility.Visible;
        Find<TextBlock>("ResultTitle").Text = title;
        Find<TextBlock>("ResultTitle").Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(error ? "#FFB3AE" : "#74DEC3"));
        Find<TextBlock>("ResultBody").Text = body;
        Find<Button>("SaveLog").Visibility = error ? Visibility.Visible : Visibility.Collapsed;
    }
    static void OpenGuide() {
        try { Prepare(); Process.Start(new ProcessStartInfo(Path.Combine(work, "安装与使用指南.html")) { UseShellExecute = true }); }
        catch (Exception e) { MessageBox.Show(e.Message, "无法打开指南"); }
    }
    static void SaveLog() {
        var dialog = new SaveFileDialog { FileName = "AI-Edit-installer-diagnostic.txt", Filter = "Text files|*.txt" };
        if (dialog.ShowDialog(window) == true) {
            try { File.WriteAllText(dialog.FileName, DateTime.UtcNow.ToString("u") + "\n" + Environment.OSVersion + "\n" + diagnostic, new UTF8Encoding(true)); }
            catch (Exception e) { MessageBox.Show(e.Message, "无法保存诊断记录"); }
        }
    }
}
