using System;
using System.Diagnostics;
using System.IO;
using System.Text;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string appDir = Path.Combine(root, "app");
            string target = Path.Combine(appDir, "chernogram.exe");
            if (!File.Exists(target)) return 2;

            var commandLine = new StringBuilder();
            foreach (string arg in args)
            {
                if (commandLine.Length > 0) commandLine.Append(' ');
                commandLine.Append('"');
                commandLine.Append((arg ?? string.Empty)
                    .Replace("\\", "\\\\")
                    .Replace("\"", "\\\""));
                commandLine.Append('"');
            }

            var info = new ProcessStartInfo
            {
                FileName = target,
                WorkingDirectory = appDir,
                UseShellExecute = false,
                Arguments = commandLine.ToString()
            };
            Process.Start(info);
            return 0;
        }
        catch
        {
            return 1;
        }
    }
}
