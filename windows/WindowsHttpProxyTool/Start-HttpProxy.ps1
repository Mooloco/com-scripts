param(
    [int]$Port = 0,
    [string]$ListenAddress = "127.0.0.1",
    [switch]$ShowLog
)

$ErrorActionPreference = "Stop"

function Read-ProxyPort {
    while ($true) {
        $inputPort = Read-Host "Proxy port (default 8080)"
        if ([string]::IsNullOrWhiteSpace($inputPort)) {
            return 8080
        }

        $parsed = 0
        if ([int]::TryParse($inputPort, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 65535) {
            return $parsed
        }

        Write-Host "Please enter a number between 1 and 65535." -ForegroundColor Yellow
    }
}

function Read-ListenAddress {
    $inputAddress = Read-Host "Listen address (default 127.0.0.1, use 0.0.0.0 for LAN)"
    if ([string]::IsNullOrWhiteSpace($inputAddress)) {
        return "127.0.0.1"
    }

    return $inputAddress.Trim()
}

if ($Port -eq 0) {
    $Port = Read-ProxyPort
}

if ([string]::IsNullOrWhiteSpace($ListenAddress)) {
    $ListenAddress = Read-ListenAddress
}

$source = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class LocalHttpProxy
{
    private readonly IPAddress listenAddress;
    private readonly int port;
    private readonly bool showLog;
    private TcpListener listener;
    private volatile bool stopping;

    public LocalHttpProxy(string listenAddress, int port, bool showLog)
    {
        this.listenAddress = IPAddress.Parse(listenAddress);
        this.port = port;
        this.showLog = showLog;
    }

    public void Start()
    {
        listener = new TcpListener(listenAddress, port);
        listener.Start();
        Console.WriteLine("HTTP proxy listening on {0}:{1}", listenAddress, port);
        Console.WriteLine("Press Ctrl+C to stop.");

        while (!stopping)
        {
            try
            {
                TcpClient client = listener.AcceptTcpClient();
                Task.Run(() => HandleClient(client, showLog));
            }
            catch (SocketException)
            {
                if (!stopping) throw;
            }
            catch (ObjectDisposedException)
            {
                if (!stopping) throw;
            }
        }
    }

    public void Stop()
    {
        stopping = true;
        if (listener != null)
        {
            listener.Stop();
        }
    }

    private static void HandleClient(TcpClient client, bool showLog)
    {
        using (client)
        {
            try
            {
                client.ReceiveTimeout = 30000;
                client.SendTimeout = 30000;

                NetworkStream clientStream = client.GetStream();
                byte[] headerBytes = ReadHeader(clientStream);
                if (headerBytes.Length == 0) return;

                string headerText = Encoding.ASCII.GetString(headerBytes);
                string[] lines = headerText.Split(new[] { "\r\n" }, StringSplitOptions.None);
                if (lines.Length == 0 || string.IsNullOrWhiteSpace(lines[0])) return;

                string[] requestParts = lines[0].Split(' ');
                if (requestParts.Length < 3)
                {
                    SendError(clientStream, "400 Bad Request");
                    return;
                }

                string method = requestParts[0];
                string target = requestParts[1];
                string version = requestParts[2];

                if (method.Equals("CONNECT", StringComparison.OrdinalIgnoreCase))
                {
                    HandleConnect(clientStream, target, showLog);
                    return;
                }

                HandleHttp(clientStream, method, target, version, lines, showLog);
            }
            catch (Exception ex)
            {
                Log(showLog, "[{0}] {1}", DateTime.Now.ToString("HH:mm:ss"), ex.Message);
            }
        }
    }

    private static byte[] ReadHeader(NetworkStream stream)
    {
        MemoryStream buffer = new MemoryStream();
        int matched = 0;
        byte[] end = new byte[] { 13, 10, 13, 10 };

        while (buffer.Length < 65536)
        {
            int b = stream.ReadByte();
            if (b < 0) break;

            buffer.WriteByte((byte)b);
            matched = b == end[matched] ? matched + 1 : (b == end[0] ? 1 : 0);

            if (matched == end.Length) break;
        }

        return buffer.ToArray();
    }

    private static void HandleConnect(NetworkStream clientStream, string target, bool showLog)
    {
        string host;
        int port;
        SplitHostPort(target, 443, out host, out port);

        using (TcpClient remote = new TcpClient())
        {
            remote.Connect(host, port);
            byte[] response = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\nProxy-Agent: LocalHttpProxy\r\n\r\n");
            clientStream.Write(response, 0, response.Length);

            Log(showLog, "[{0}] CONNECT {1}:{2}", DateTime.Now.ToString("HH:mm:ss"), host, port);
            RelayBoth(clientStream, remote.GetStream());
        }
    }

    private static void HandleHttp(NetworkStream clientStream, string method, string target, string version, string[] lines, bool showLog)
    {
        Uri uri;
        string host;
        int port;
        string path;

        if (Uri.TryCreate(target, UriKind.Absolute, out uri))
        {
            host = uri.Host;
            port = uri.Port > 0 ? uri.Port : (uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase) ? 443 : 80);
            path = string.IsNullOrEmpty(uri.PathAndQuery) ? "/" : uri.PathAndQuery;
        }
        else
        {
            string hostHeader = GetHeader(lines, "Host");
            if (string.IsNullOrWhiteSpace(hostHeader))
            {
                SendError(clientStream, "400 Bad Request");
                return;
            }

            SplitHostPort(hostHeader.Trim(), 80, out host, out port);
            path = string.IsNullOrEmpty(target) ? "/" : target;
        }

        using (TcpClient remote = new TcpClient())
        {
            remote.Connect(host, port);
            NetworkStream remoteStream = remote.GetStream();
            string forwardedHeader = BuildForwardHeader(method, path, version, lines);
            byte[] forwardedBytes = Encoding.ASCII.GetBytes(forwardedHeader);
            remoteStream.Write(forwardedBytes, 0, forwardedBytes.Length);

            Log(showLog, "[{0}] {1} {2}:{3}{4}", DateTime.Now.ToString("HH:mm:ss"), method, host, port, path);
            RelayBoth(clientStream, remoteStream);
        }
    }

    private static void Log(bool showLog, string format, params object[] args)
    {
        if (showLog)
        {
            Console.WriteLine(format, args);
        }
    }

    private static string BuildForwardHeader(string method, string path, string version, string[] lines)
    {
        StringBuilder builder = new StringBuilder();
        builder.Append(method).Append(' ').Append(path).Append(' ').Append(version).Append("\r\n");

        bool hasConnection = false;
        for (int i = 1; i < lines.Length; i++)
        {
            string line = lines[i];
            if (string.IsNullOrEmpty(line)) break;

            int colon = line.IndexOf(':');
            if (colon <= 0) continue;

            string name = line.Substring(0, colon).Trim();
            if (name.Equals("Proxy-Connection", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (name.Equals("Connection", StringComparison.OrdinalIgnoreCase))
            {
                hasConnection = true;
                builder.Append("Connection: close\r\n");
                continue;
            }

            builder.Append(line).Append("\r\n");
        }

        if (!hasConnection)
        {
            builder.Append("Connection: close\r\n");
        }

        builder.Append("\r\n");
        return builder.ToString();
    }

    private static string GetHeader(string[] lines, string headerName)
    {
        for (int i = 1; i < lines.Length; i++)
        {
            string line = lines[i];
            if (string.IsNullOrEmpty(line)) break;

            int colon = line.IndexOf(':');
            if (colon <= 0) continue;

            string name = line.Substring(0, colon).Trim();
            if (name.Equals(headerName, StringComparison.OrdinalIgnoreCase))
            {
                return line.Substring(colon + 1).Trim();
            }
        }

        return null;
    }

    private static void SplitHostPort(string value, int defaultPort, out string host, out int port)
    {
        host = value;
        port = defaultPort;

        if (value.StartsWith("["))
        {
            int end = value.IndexOf(']');
            if (end > 0)
            {
                host = value.Substring(1, end - 1);
                if (value.Length > end + 2 && value[end + 1] == ':')
                {
                    int.TryParse(value.Substring(end + 2), out port);
                }
            }
            return;
        }

        int colon = value.LastIndexOf(':');
        if (colon > 0 && value.IndexOf(':') == colon)
        {
            host = value.Substring(0, colon);
            int.TryParse(value.Substring(colon + 1), out port);
        }
    }

    private static void RelayBoth(Stream left, Stream right)
    {
        Task leftToRight = Pump(left, right);
        Task rightToLeft = Pump(right, left);
        Task.WaitAny(leftToRight, rightToLeft);
    }

    private static async Task Pump(Stream input, Stream output)
    {
        byte[] buffer = new byte[81920];
        try
        {
            while (true)
            {
                int read = await input.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                if (read <= 0) break;
                await output.WriteAsync(buffer, 0, read).ConfigureAwait(false);
                await output.FlushAsync().ConfigureAwait(false);
            }
        }
        catch
        {
        }
    }

    private static void SendError(NetworkStream stream, string status)
    {
        byte[] response = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + "\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
        stream.Write(response, 0, response.Length);
    }
}
"@

Add-Type -TypeDefinition $source -Language CSharp

$proxy = [LocalHttpProxy]::new($ListenAddress, $Port, [bool]$ShowLog)

try {
    $null = [Console]::TreatControlCAsInput = $false
    [Console]::CancelKeyPress.Add({
        param($sender, $eventArgs)
        $eventArgs.Cancel = $true
        $script:stopRequested = $true
        if ($script:proxy -ne $null) {
            $script:proxy.Stop()
        }
    })
}
catch {
    Write-Verbose "Console Ctrl+C handler is not available in this host."
}

try {
    $script:proxy = $proxy
    $proxy.Start()
}
finally {
    $proxy.Stop()
    Write-Host "Proxy stopped."
}
