// Deep Finds launcher: installs the game from the latest GitHub release, keeps the game and
// the launcher itself up to date, and starts the game. Players never need Git or Godot.
//
// Build it with launcher/build.ps1, which uses the C# compiler that ships with Windows.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("Deep Finds Launcher")]
[assembly: AssemblyProduct("Deep Finds")]
[assembly: AssemblyVersion(DeepFindsLauncher.Program.Version)]
[assembly: AssemblyFileVersion(DeepFindsLauncher.Program.Version)]

namespace DeepFindsLauncher
{
    static class Program
    {
        // Bump this whenever the launcher changes: installed launchers replace themselves
        // only with a release launcher that has a higher version.
        public const string Version = "1.0.0.0";

        [DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main()
        {
            try { SetProcessDPIAware(); } catch (Exception) { }
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new LauncherForm());
        }
    }

    class Asset
    {
        public string Name, Url, Sha256;
        public long Size;
    }

    class Release
    {
        public string Tag, Notes, Date;
        public Asset Game, Launcher;
    }

    class LauncherForm : Form
    {
        const string Repo = "Thyestee/Project-Dev";
        const string GameExe = "DeepFinds.exe";
        const string GameProcess = "DeepFinds";
        const string LauncherAsset = "DeepFindsLauncher.exe";

        public static readonly Color Bg = Color.FromArgb(24, 21, 20);
        public static readonly Color PanelColor = Color.FromArgb(38, 34, 31);
        public static readonly Color Gold = Color.FromArgb(255, 214, 89);
        public static readonly Color TextColor = Color.FromArgb(235, 230, 220);
        public static readonly Color Dim = Color.FromArgb(150, 140, 128);
        public static readonly Color Good = Color.FromArgb(140, 220, 140);
        public static readonly Color Warn = Color.FromArgb(255, 160, 110);

        readonly string root, gameDir, versionFile, settingsFile, notesFile;
        readonly HttpClient http;
        string latestTag;
        bool busy;

        Label versionLabel, statusLabel;
        TextBox news;
        ProgressStrip bar;
        Button checkButton, playButton;
        CheckBox closeBox;

        public LauncherForm()
        {
            root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeepFinds");
            gameDir = Path.Combine(root, "game");
            versionFile = Path.Combine(root, "installed_version.txt");
            settingsFile = Path.Combine(root, "launcher_settings.txt");
            notesFile = Path.Combine(root, "whats_new.txt");

            http = new HttpClient();
            http.Timeout = TimeSpan.FromMinutes(30);
            http.DefaultRequestHeaders.UserAgent.ParseAdd("DeepFindsLauncher/" + Program.Version);

            BuildUi();
        }

        // --- UI ------------------------------------------------------------------------

        void BuildUi()
        {
            SuspendLayout();
            AutoScaleDimensions = new SizeF(96f, 96f);
            AutoScaleMode = AutoScaleMode.Dpi;
            Text = "Deep Finds Launcher";
            ClientSize = new Size(640, 524);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            BackColor = Bg;
            ForeColor = TextColor;
            Font = new Font("Segoe UI", 10f);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

            var header = new Header();
            header.SetBounds(0, 0, 640, 150);
            Controls.Add(header);

            versionLabel = AddLabel(24, 162, 592, 22, Dim, "");

            var newsTitle = AddLabel(24, 194, 592, 20, Dim, "WHAT'S NEW");
            newsTitle.Font = new Font("Segoe UI", 9f, FontStyle.Bold);

            news = new TextBox();
            news.SetBounds(24, 216, 592, 160);
            news.Multiline = true;
            news.ReadOnly = true;
            news.ScrollBars = ScrollBars.Vertical;
            news.BorderStyle = BorderStyle.FixedSingle;
            news.BackColor = PanelColor;
            news.ForeColor = TextColor;
            news.Font = new Font("Segoe UI", 9.5f);
            news.TabStop = false;
            Controls.Add(news);

            statusLabel = AddLabel(24, 386, 592, 22, TextColor, "");

            bar = new ProgressStrip();
            bar.SetBounds(24, 412, 592, 6);
            bar.BackColor = PanelColor;
            bar.ForeColor = Gold;
            bar.Visible = false;
            Controls.Add(bar);

            checkButton = AddButton("Check for updates", 24, 434, 170, 40);
            checkButton.Click += async (s, e) => await CheckForUpdates();

            playButton = AddButton("PLAY", 436, 428, 180, 52);
            playButton.Font = new Font("Segoe UI", 15f, FontStyle.Bold);
            playButton.Click += (s, e) => Play();
            AcceptButton = playButton;

            closeBox = new CheckBox();
            closeBox.SetBounds(24, 488, 330, 24);
            closeBox.Text = "Close the launcher when the game starts";
            closeBox.ForeColor = Dim;
            closeBox.Checked = ReadCloseOnPlay();
            closeBox.CheckedChanged += (s, e) => SaveCloseOnPlay(closeBox.Checked);
            Controls.Add(closeBox);

            var link = new LinkLabel();
            link.SetBounds(360, 491, 256, 20);
            link.TextAlign = ContentAlignment.MiddleRight;
            link.Font = new Font("Segoe UI", 8.5f);
            link.Text = "Releases on GitHub   ·   Launcher " + new Version(Program.Version).ToString(2);
            link.LinkArea = new LinkArea(0, "Releases on GitHub".Length);
            link.LinkColor = Dim;
            link.ActiveLinkColor = Gold;
            link.ForeColor = Dim;
            link.LinkClicked += (s, e) => OpenUrl("https://github.com/" + Repo + "/releases");
            Controls.Add(link);

            ResumeLayout(false);

            Shown += async (s, e) =>
            {
                ShowCachedNotes();
                ShowVersions();
                SetBusy(false);
                playButton.Focus();
                RemoveOldLauncher();
                await CheckForUpdates();
            };
        }

        Label AddLabel(int x, int y, int w, int h, Color color, string text)
        {
            var label = new Label();
            label.SetBounds(x, y, w, h);
            label.ForeColor = color;
            label.Text = text;
            Controls.Add(label);
            return label;
        }

        Button AddButton(string text, int x, int y, int w, int h)
        {
            var b = new Button();
            b.SetBounds(x, y, w, h);
            b.Text = text;
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderColor = Color.FromArgb(110, 85, 50);
            b.BackColor = PanelColor;
            b.ForeColor = TextColor;
            b.Cursor = Cursors.Hand;
            b.UseVisualStyleBackColor = false;
            Controls.Add(b);
            return b;
        }

        void SetStatus(string text, Color color)
        {
            statusLabel.Text = text;
            statusLabel.ForeColor = color;
        }

        void SetBusy(bool value)
        {
            busy = value;
            if (!value) bar.Visible = false;
            checkButton.Enabled = !value;
            bool canPlay = !value && InstalledVersion() != null;
            playButton.Enabled = canPlay;
            playButton.BackColor = canPlay ? Gold : PanelColor;
            playButton.ForeColor = canPlay ? Color.FromArgb(30, 24, 18) : Dim;
            playButton.FlatAppearance.BorderColor = canPlay ? Gold : Color.FromArgb(70, 60, 50);
        }

        void ShowVersions()
        {
            string installed = InstalledVersion();
            versionLabel.Text = "Installed: " + (installed ?? "not yet") + "        Latest: " + (latestTag ?? "unknown");
        }

        void ShowCachedNotes()
        {
            try { if (File.Exists(notesFile)) news.Text = File.ReadAllText(notesFile); } catch (Exception) { }
        }

        void ShowNotes(List<Release> releases)
        {
            var sb = new StringBuilder();
            foreach (Release r in releases.Take(8))
            {
                string date = r.Date.Length >= 10 ? r.Date.Substring(0, 10) : r.Date;
                sb.Append(r.Tag).Append("    ").Append(date).Append("\r\n");
                sb.Append(CleanNotes(r.Notes)).Append("\r\n\r\n");
            }
            news.Text = releases.Count == 0 ? "Nothing has been released yet." : sb.ToString().TrimEnd();
            try
            {
                Directory.CreateDirectory(root);
                File.WriteAllText(notesFile, news.Text);
            }
            catch (Exception) { }
        }

        // Release notes are Markdown; show them as plain text.
        static string CleanNotes(string markdown)
        {
            var sb = new StringBuilder();
            foreach (string raw in markdown.Replace("\r", "").Split('\n'))
            {
                string line = Regex.Replace(raw, @"\[([^\]]+)\]\([^)]*\)", "$1").Replace("**", "").Replace("`", "").TrimEnd();
                if (line.StartsWith("#")) line = line.TrimStart('#').Trim().ToUpperInvariant();
                sb.Append("   ").Append(line).Append("\r\n");
            }
            return sb.ToString().TrimEnd();
        }

        // --- Update flow -----------------------------------------------------------------

        async Task CheckForUpdates()
        {
            if (busy) return;
            SetBusy(true);
            SetStatus("Checking for updates...", TextColor);

            List<Release> releases;
            try
            {
                releases = await FetchReleases();
            }
            catch (Exception)
            {
                SetBusy(false);
                string have = InstalledVersion();
                if (have != null) SetStatus("Couldn't reach GitHub. You can still play " + have + ".", Warn);
                else SetStatus("Couldn't reach GitHub. Connect to the internet to install the game.", Warn);
                return;
            }

            ShowNotes(releases);
            Release latest = releases.FirstOrDefault(r => r.Game != null);
            latestTag = latest == null ? null : latest.Tag;
            ShowVersions();
            if (latest == null)
            {
                SetBusy(false);
                SetStatus("No version of the game has been published yet.", Dim);
                return;
            }

            if (latest.Launcher != null && await UpdateLauncher(latest.Launcher)) return;

            string installed = InstalledVersion();
            if (installed == latest.Tag)
            {
                SetBusy(false);
                SetStatus("Up to date.", Good);
                return;
            }
            if (Process.GetProcessesByName(GameProcess).Length > 0)
            {
                SetBusy(false);
                SetStatus(latest.Tag + " is out. Close the game, then press \"Check for updates\".", Warn);
                return;
            }

            try
            {
                await InstallGame(latest);
                SetBusy(false);
                SetStatus(installed == null ? "Deep Finds " + latest.Tag + " is installed. Have fun!" : "Updated to " + latest.Tag + ".", Good);
            }
            catch (Exception ex)
            {
                SetBusy(false);
                string message = "The download failed: " + ex.Message;
                if (installed != null) message += " You can still play " + installed + ".";
                SetStatus(message, Warn);
            }
            ShowVersions();
        }

        async Task<List<Release>> FetchReleases()
        {
            var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/repos/" + Repo + "/releases?per_page=10");
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20)))
            using (HttpResponseMessage response = await http.SendAsync(request, timeout.Token))
            {
                response.EnsureSuccessStatusCode();
                string json = await response.Content.ReadAsStringAsync();
                var serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = int.MaxValue;
                var releases = new List<Release>();
                foreach (object item in (object[])serializer.DeserializeObject(json))
                {
                    var r = (Dictionary<string, object>)item;
                    if (Flag(r, "draft") || Flag(r, "prerelease")) continue;
                    var release = new Release { Tag = Str(r, "tag_name"), Notes = Str(r, "body"), Date = Str(r, "published_at") };
                    foreach (object a in (object[])r["assets"])
                    {
                        var d = (Dictionary<string, object>)a;
                        var asset = new Asset { Name = Str(d, "name"), Url = Str(d, "browser_download_url"), Size = Convert.ToInt64(d["size"]) };
                        string digest = Str(d, "digest");
                        if (digest.StartsWith("sha256:")) asset.Sha256 = digest.Substring(7).ToLowerInvariant();
                        if (asset.Name == LauncherAsset) release.Launcher = asset;
                        else if (asset.Name.StartsWith("DeepFinds-") && asset.Name.EndsWith("-windows.zip")) release.Game = asset;
                    }
                    releases.Add(release);
                }
                return releases;
            }
        }

        static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) && v != null ? v.ToString() : "";
        }

        static bool Flag(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) && v is bool && (bool)v;
        }

        async Task InstallGame(Release release)
        {
            Directory.CreateDirectory(root);
            string zip = Path.Combine(root, "download.zip");
            string staging = Path.Combine(root, "staging");
            string old = Path.Combine(root, "game.old");

            await Download(release.Game, zip, "Downloading Deep Finds " + release.Tag);
            SetStatus("Installing " + release.Tag + "...", TextColor);
            await Task.Run(() =>
            {
                Verify(release.Game, zip);
                DeleteDirectory(staging);
                ZipFile.ExtractToDirectory(zip, staging);
                if (!File.Exists(Path.Combine(staging, GameExe))) throw new Exception("the download doesn't contain " + GameExe + ".");
                DeleteDirectory(old);
                if (Directory.Exists(gameDir)) Directory.Move(gameDir, old);
                try
                {
                    Directory.Move(staging, gameDir);
                }
                catch (Exception)
                {
                    if (Directory.Exists(old)) Directory.Move(old, gameDir);
                    throw;
                }
                DeleteDirectory(old);
                File.Delete(zip);
            });
            File.WriteAllText(versionFile, release.Tag);
        }

        // Replaces this launcher with the release's launcher when that one has a higher version,
        // then restarts. Returns true when the restart is under way.
        async Task<bool> UpdateLauncher(Asset asset)
        {
            string exe = Application.ExecutablePath;
            if (asset.Sha256 == null) return false;
            if (await Task.Run(() => Sha256Of(exe)) == asset.Sha256) return false;

            string fresh = exe + ".new", old = exe + ".old";
            try
            {
                await Download(asset, fresh, "Downloading the new launcher");
                Verify(asset, fresh);
                var theirs = new Version(FileVersionInfo.GetVersionInfo(fresh).FileVersion);
                if (theirs <= new Version(Program.Version))
                {
                    File.Delete(fresh);
                    return false;
                }
                if (File.Exists(old)) File.Delete(old);
                File.Move(exe, old);
                File.Move(fresh, exe);
            }
            catch (Exception)
            {
                // No write access to the launcher's folder, or the download failed: keep this one.
                try { if (!File.Exists(exe) && File.Exists(old)) File.Move(old, exe); } catch (Exception) { }
                try { File.Delete(fresh); } catch (Exception) { }
                return false;
            }
            Process.Start(exe);
            Close();
            return true;
        }

        // The previous launcher may still be exiting when the new one starts.
        async void RemoveOldLauncher()
        {
            string old = Application.ExecutablePath + ".old";
            for (int i = 0; i < 20 && File.Exists(old); i++)
            {
                try { File.Delete(old); return; } catch (Exception) { }
                await Task.Delay(500);
            }
        }

        async Task Download(Asset asset, string path, string label)
        {
            bar.Value = 0f;
            bar.Visible = true;
            using (HttpResponseMessage response = await http.GetAsync(asset.Url, HttpCompletionOption.ResponseHeadersRead))
            {
                response.EnsureSuccessStatusCode();
                long total = response.Content.Headers.ContentLength ?? asset.Size;
                using (Stream input = await response.Content.ReadAsStreamAsync())
                using (FileStream output = File.Create(path))
                {
                    var buffer = new byte[81920];
                    long done = 0;
                    int read;
                    DateTime shown = DateTime.MinValue;
                    while ((read = await input.ReadAsync(buffer, 0, buffer.Length)) > 0)
                    {
                        await output.WriteAsync(buffer, 0, read);
                        done += read;
                        if ((DateTime.UtcNow - shown).TotalMilliseconds > 100)
                        {
                            shown = DateTime.UtcNow;
                            ShowProgress(label, done, total);
                        }
                    }
                    ShowProgress(label, done, total);
                }
            }
        }

        void ShowProgress(string label, long done, long total)
        {
            const double MB = 1024.0 * 1024.0;
            if (total > 0)
            {
                bar.Value = (float)done / total;
                SetStatus(string.Format("{0}...   {1:0.0} / {2:0.0} MB", label, done / MB, total / MB), TextColor);
            }
            else
            {
                SetStatus(string.Format("{0}...   {1:0.0} MB", label, done / MB), TextColor);
            }
        }

        static void Verify(Asset asset, string path)
        {
            if (asset.Sha256 != null)
            {
                if (Sha256Of(path) != asset.Sha256) throw new Exception("the file was damaged on the way. Try again.");
            }
            else if (asset.Size > 0 && new FileInfo(path).Length != asset.Size)
            {
                throw new Exception("the file is incomplete. Try again.");
            }
        }

        static string Sha256Of(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
            }
        }

        static void DeleteDirectory(string path)
        {
            if (Directory.Exists(path)) Directory.Delete(path, true);
        }

        // --- Game and settings --------------------------------------------------------------

        string InstalledVersion()
        {
            try
            {
                if (!File.Exists(Path.Combine(gameDir, GameExe)) || !File.Exists(versionFile)) return null;
                return File.ReadAllText(versionFile).Trim();
            }
            catch (Exception)
            {
                return null;
            }
        }

        void Play()
        {
            string exe = Path.Combine(gameDir, GameExe);
            if (busy || !File.Exists(exe)) return;
            try
            {
                var start = new ProcessStartInfo(exe);
                start.WorkingDirectory = gameDir;
                Process.Start(start);
            }
            catch (Exception ex)
            {
                SetStatus("Couldn't start the game: " + ex.Message, Warn);
                return;
            }
            if (closeBox.Checked) Close();
            else SetStatus("Deep Finds is running. Happy digging!", Good);
        }

        bool ReadCloseOnPlay()
        {
            try { return !File.Exists(settingsFile) || File.ReadAllText(settingsFile).Trim() != "close_on_play=0"; }
            catch (Exception) { return true; }
        }

        void SaveCloseOnPlay(bool value)
        {
            try
            {
                Directory.CreateDirectory(root);
                File.WriteAllText(settingsFile, value ? "close_on_play=1" : "close_on_play=0");
            }
            catch (Exception) { }
        }

        static void OpenUrl(string url)
        {
            try { Process.Start(url); } catch (Exception) { }
        }
    }

    // A thin gold bar for download progress.
    class ProgressStrip : Control
    {
        float value;

        public ProgressStrip()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        }

        public float Value
        {
            get { return value; }
            set { this.value = Math.Max(0f, Math.Min(1f, value)); Invalidate(); }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            using (var brush = new SolidBrush(ForeColor))
                e.Graphics.FillRectangle(brush, 0, 0, (int)(ClientSize.Width * value), ClientSize.Height);
        }
    }

    // The banner: a strip of pixel-art ground with a buried gem, under the title.
    class Header : Control
    {
        static readonly string[] Gem = { "..oooo..", ".oLWLMo.", "oLMLMMDo", ".oMMDDo.", "..oDDo..", "...oo..." };

        public Header()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            float scale = g.DpiX / 96f;
            int w = ClientSize.Width, h = ClientSize.Height;
            int px = Math.Max(4, (int)Math.Round(8 * scale));
            int groundTop = h - px * 7;

            using (var sky = new LinearGradientBrush(new Rectangle(0, 0, w, groundTop + 1), Color.FromArgb(34, 58, 102), Color.FromArgb(128, 184, 232), 90f))
                g.FillRectangle(sky, 0, 0, w, groundTop);
            using (var cloud = new SolidBrush(Color.FromArgb(70, 255, 255, 255)))
            {
                DrawCloud(g, cloud, (int)(w * 0.56), px * 3, px);
                DrawCloud(g, cloud, (int)(w * 0.82), px * 6, px);
            }

            var rng = new Random(7);
            Color grass = Color.FromArgb(108, 192, 67), grassLight = Color.FromArgb(136, 214, 90), grassDark = Color.FromArgb(79, 154, 46);
            Color dirt = Color.FromArgb(138, 90, 54), dirtDark = Color.FromArgb(107, 68, 40), dirtLight = Color.FromArgb(160, 109, 67);
            for (int row = 0; row < 7; row++)
            {
                for (int col = 0; col * px < w; col++)
                {
                    Color c;
                    int roll = rng.Next(9);
                    if (row == 0) c = roll < 2 ? grassLight : grass;
                    else if (row == 1) c = roll < 4 ? grassDark : dirt;
                    else c = roll == 0 ? dirtDark : roll == 1 ? dirtLight : dirt;
                    using (var brush = new SolidBrush(c))
                        g.FillRectangle(brush, col * px, groundTop + row * px, px, px);
                }
            }
            using (var depth = new LinearGradientBrush(new Rectangle(0, groundTop + px * 2, w, px * 5 + 1), Color.FromArgb(0, 0, 0, 0), Color.FromArgb(110, 0, 0, 0), 90f))
                g.FillRectangle(depth, 0, groundTop + px * 2, w, px * 5);

            int gp = Math.Max(2, px / 2);
            DrawGem(g, w - px * 14, groundTop + px * 3 + gp, gp);
            using (var sparkle = new SolidBrush(Color.FromArgb(255, 243, 176)))
            {
                g.FillRectangle(sparkle, w - px * 14 + gp * 10, groundTop + px * 3, gp, gp);
                g.FillRectangle(sparkle, w - px * 14 - gp * 3, groundTop + px * 5 + gp, gp, gp);
            }

            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            using (var title = new Font("Segoe UI Black", 30f))
            using (var subtitle = new Font("Segoe UI Semibold", 10.5f))
            using (var shadow = new SolidBrush(Color.FromArgb(150, 0, 0, 0)))
            using (var gold = new SolidBrush(LauncherForm.Gold))
            using (var light = new SolidBrush(Color.FromArgb(238, 242, 248)))
            {
                float x = 22 * scale, y = 10 * scale;
                g.DrawString("DEEP FINDS", title, shadow, x + 2 * scale, y + 3 * scale);
                g.DrawString("DEEP FINDS", title, gold, x, y);
                float sy = y + title.GetHeight(g) - 4 * scale;
                const string tagline = "Lost treasures are waiting under the field.";
                g.DrawString(tagline, subtitle, shadow, x + 4 * scale, sy + 1 * scale);
                g.DrawString(tagline, subtitle, light, x + 3 * scale, sy);
            }
        }

        static void DrawCloud(Graphics g, Brush brush, int x, int y, int px)
        {
            g.FillRectangle(brush, x + px, y, px * 3, px);
            g.FillRectangle(brush, x, y + px, px * 6, px);
        }

        static void DrawGem(Graphics g, int x, int y, int p)
        {
            for (int row = 0; row < Gem.Length; row++)
            {
                for (int col = 0; col < Gem[row].Length; col++)
                {
                    Color c;
                    switch (Gem[row][col])
                    {
                        case 'o': c = Color.FromArgb(184, 116, 26); break;
                        case 'L': c = Color.FromArgb(255, 226, 122); break;
                        case 'W': c = Color.FromArgb(255, 248, 214); break;
                        case 'M': c = Color.FromArgb(245, 184, 51); break;
                        case 'D': c = Color.FromArgb(217, 149, 31); break;
                        default: continue;
                    }
                    using (var brush = new SolidBrush(c))
                        g.FillRectangle(brush, x + col * p, y + row * p, p, p);
                }
            }
        }
    }
}
