class Extmem < Formula
  desc "Local external memory service with semantic search"
  homepage "https://github.com/ut0s/homebrew-extmem"
  url "https://github.com/ut0s/homebrew-extmem/releases/download/v0.1.2/extmem-v0.1.2.tar.gz"
  version "0.1.2"
  sha256 "4362bd375ec84235589d83c8d00b79ccf10afc9b066e3b4e3fb2471379063679"
  license :cannot_represent

  depends_on "node@22"
  depends_on "pnpm" => :build
  depends_on "python@3.13" => :build

  def install
    ENV.prepend_path "PATH", Formula["node@22"].opt_bin
    ENV["npm_config_python"] = (Formula["python@3.13"].opt_bin/"python3.13").to_s
    system Formula["pnpm"].opt_bin/"pnpm", "install", "--prod", "--frozen-lockfile"

    libexec.install "dist", "node_modules", "package.json", "public", "plugins", "scripts"
    chmod 0555, libexec/"dist/cli.js"
    (bin/"extmem").write <<~SH
      #!/bin/sh
      exec "#{Formula["node@22"].opt_bin}/node" "#{opt_libexec}/dist/cli.js" "$@"
    SH
    chmod 0555, bin/"extmem"
  end

  def post_install
    (var/"extmem").mkpath
    (var/"log").mkpath
    (etc/"extmem").mkpath
    config = etc/"extmem/config.json"
    config.write(JSON.pretty_generate({ dataPath: (var/"extmem").to_s })) unless config.exist?
  end

  service do
    run [opt_bin/"extmem", "--config", etc/"extmem/config.json", "--port", "43111"]
    working_dir var/"extmem"
    environment_variables PATH: std_service_path_env, EXTMEM_NO_OPEN: "1"
    keep_alive true
    log_path var/"log/extmem.log"
    error_log_path var/"log/extmem-error.log"
  end

  def caveats
    <<~EOS
      Web service: brew services start extmem (http://127.0.0.1:43111)
      Configuration: #{etc}/extmem/config.json
      Default data: #{var}/extmem
      Existing data is not migrated automatically. Set dataPath before starting.
      MCP stdio: extmem mcp --config #{etc}/extmem/config.json
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/extmem --help")

    port = free_port
    pid = fork do
      ENV["EXTMEM_NO_OPEN"] = "1"
      exec (bin/"extmem").to_s, "--config", (testpath/"config.json").to_s, "--port", port.to_s
    end
    begin
      response = nil
      30.times do
        begin
          response = shell_output("curl -sS http://127.0.0.1:#{port}/api/memos")
          break if response.include?("[")
        rescue RuntimeError
          sleep 0.2
        end
      end
      assert_match "[", response
    ensure
      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end
end
