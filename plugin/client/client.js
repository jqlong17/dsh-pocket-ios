window.__ModuleLoader__.load({
  id: "dsh-pocket-ios",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    var React = require("react");

    var APP_STORE_URL = "https://apps.apple.com/app/id6832288744";
    var REPO_URL = "https://github.com/jqlong17/dsh-pocket-ios";
    var DOC_URL = "https://dsh-pocket.docs.notta.uk";
    var QR_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100%\" height=\"100%\" viewBox=\"0 0 37 37\" shape-rendering=\"crispEdges\"><path fill=\"#ffffff\" d=\"M0 0h37v37H0z\"/><path stroke=\"#000000\" d=\"M4 4.5h7m3 0h1m4 0h5m2 0h7M4 5.5h1m5 0h1m2 0h1m7 0h1m2 0h1m1 0h1m5 0h1M4 6.5h1m1 0h3m1 0h1m1 0h1m5 0h1m1 0h1m3 0h1m1 0h1m1 0h3m1 0h1M4 7.5h1m1 0h3m1 0h1m1 0h2m7 0h1m1 0h1m2 0h1m1 0h3m1 0h1M4 8.5h1m1 0h3m1 0h1m1 0h8m2 0h3m1 0h1m1 0h3m1 0h1M4 9.5h1m5 0h1m1 0h2m1 0h5m2 0h1m1 0h1m1 0h1m5 0h1M4 10.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M12 11.5h1m1 0h1m1 0h2m1 0h2m2 0h2M4 12.5h1m1 0h5m5 0h1m1 0h2m1 0h1m1 0h1m2 0h5M8 13.5h1m5 0h2m7 0h4m1 0h1m3 0h1M5 14.5h1m3 0h2m1 0h1m1 0h3m5 0h1m1 0h1m1 0h2M4 15.5h5m6 0h2m1 0h1m1 0h1m1 0h2m1 0h2m1 0h2m1 0h1M5 16.5h3m1 0h2m1 0h2m5 0h3m5 0h1m1 0h2M4 17.5h4m3 0h3m1 0h1m1 0h2m4 0h6m3 0h1M8 18.5h3m3 0h1m2 0h4m1 0h1m2 0h1m2 0h3M5 19.5h2m2 0h1m1 0h1m3 0h1m1 0h1m1 0h1m2 0h3m3 0h1m2 0h1M4 20.5h2m2 0h1m1 0h6m2 0h1m1 0h4m3 0h1m1 0h2M4 21.5h6m1 0h1m1 0h3m5 0h3m2 0h3m1 0h1m1 0h1M4 22.5h1m4 0h3m2 0h2m3 0h3m2 0h2m2 0h1m1 0h1M4 23.5h1m2 0h3m3 0h1m1 0h2m1 0h1m5 0h2m2 0h1m2 0h1M4 24.5h1m1 0h3m1 0h1m3 0h3m4 0h1m2 0h5m1 0h3M12 25.5h3m1 0h3m2 0h2m1 0h1m3 0h5M4 26.5h7m6 0h2m3 0h3m1 0h1m1 0h3M4 27.5h1m5 0h1m1 0h6m5 0h2m3 0h1M4 28.5h1m1 0h3m1 0h1m1 0h5m1 0h1m2 0h1m2 0h5m1 0h1m1 0h1M4 29.5h1m1 0h3m1 0h1m1 0h2m8 0h1m4 0h1m1 0h2M4 30.5h1m1 0h3m1 0h1m1 0h1m1 0h1m3 0h2m3 0h2m1 0h6M4 31.5h1m5 0h1m3 0h2m3 0h1m2 0h1m1 0h2m1 0h3m1 0h1M4 32.5h7m1 0h2m1 0h1m1 0h4m1 0h2m1 0h1m2 0h1m1 0h1\"/></svg>";


    // 跟随 DSH 设置页的语言：locale 服务会同步 <html lang>，这里监听变化。
    function currentLang() {
      try {
        var tag = (document.documentElement.lang || navigator.language || "zh").toLowerCase();
        return tag.indexOf("zh") === 0 ? "zh" : "en";
      } catch (e) { return "zh"; }
    }
    function useLang() {
      var state = React.useState(currentLang());
      React.useEffect(function () {
        if (typeof MutationObserver === "undefined") return undefined;
        var observer = new MutationObserver(function () { state[1](currentLang()); });
        observer.observe(document.documentElement, { attributes: true, attributeFilter: ["lang"] });
        return function () { observer.disconnect(); };
      }, []);
      return state[0];
    }
    function makeT(lang) { return function (zh, en) { return lang === "zh" ? zh : en; }; }

    function linkStyle(primary) {
      return {
        display: "inline-flex", alignItems: "center", gap: 6,
        padding: "7px 12px", borderRadius: 999, fontSize: 13, fontWeight: 600,
        textDecoration: "none", color: primary ? "#fff" : "#147A5E",
        background: primary ? "#147A5E" : "rgba(20,122,94,.08)",
        border: primary ? "1px solid #147A5E" : "1px solid rgba(20,122,94,.25)"
      };
    }
    var chipStyle = { display: "inline-flex", alignItems: "center", padding: "3px 9px", borderRadius: 999, fontSize: 12, fontWeight: 500, color: "#147A5E", background: "rgba(20,122,94,.08)", border: "1px solid rgba(20,122,94,.22)", cursor: "pointer" };
    var chipPrimary = { ...chipStyle, color: "#fff", background: "#147A5E", border: "1px solid #147A5E" };

    function copyText(text) {
      try { if (navigator.clipboard && window.isSecureContext) { navigator.clipboard.writeText(text); return true; } } catch (e) {}
      try {
        var area = document.createElement("textarea");
        area.value = text; area.style.position = "fixed"; area.style.top = "-1000px"; area.style.opacity = "0";
        document.body.appendChild(area); area.focus(); area.select();
        var ok = document.execCommand("copy");
        document.body.removeChild(area);
        return ok;
      } catch (e) { return false; }
    }

    function unwrapRpc(result) {
      if (result && typeof result === "object" && "ok" in result) {
        if (!result.ok) return Promise.reject(new Error((result.error && result.error.message) || makeT(currentLang())("RPC 失败", "RPC failed")));
        return result.value !== undefined ? result.value : result;
      }
      if (result && typeof result === "object" && result.result) return unwrapRpc(result.result);
      return result;
    }

    // ===== 单个连接卡片：配对二维码 + 地址 + 密码管理 =====
    function AccessPanelCard(props) {
      var pairState = React.useState({ loading: true, error: null, data: null });
      var pairValue = pairState[0];
      var setPair = pairState[1];
      var remainingState = React.useState(300);
      var remaining = remainingState[0];
      var setRemaining = remainingState[1];
      var statusState = React.useState(null);
      var status = statusState[0];
      var setStatus = statusState[1];
      var loadingState = React.useState(true);
      var loading = loadingState[0];
      var setLoading = loadingState[1];

      var showPinState = React.useState(false);
      var showPin = showPinState[0];
      var setShowPin = showPinState[1];
      var copiedState = React.useState(null);
      var copied = copiedState[0];
      var setCopied = copiedState[1];
      var editingState = React.useState(false);
      var editing = editingState[0];
      var setEditing = editingState[1];
      var customState = React.useState("");
      var customPin = customState[0];
      var setCustomPin = customState[1];
      var busyState = React.useState(false);
      var busy = busyState[0];
      var setBusy = busyState[1];
      var pollRef = React.useRef(null);
      var errorState = React.useState(null);
      var actionError = errorState[0];
      var setActionError = errorState[1];

      var setMode = function (mode) {
        if (!props.rpcCall) return;
        setBusy(true); setActionError(null);
        Promise.resolve(props.rpcCall("mode.set", { mode: mode })).then(unwrapRpc).then(function (st) {
          // mode.set 返回的是轻量状态（address 为 null，避免切到 Cloudflare 时被
          // 下载/注册拖到超时）。直接拿它渲染会显示「当前方式还没有地址」，
          // 所以立刻再拉一次完整状态。
          setStatus(st || null); setBusy(false);
          refreshStatus();
          // 切了模式，二维码必须重新生成（Cloudflare / 局域网的地址都不同）
          generatePair();
        }).catch(function (e) { setBusy(false); setActionError(String((e && e.message) || e)); });
      };

      var refreshStatus = function () {
        if (!props.rpcCall) { setLoading(false); return; }
        Promise.resolve(props.rpcCall("tailscale.status", {})).then(unwrapRpc).then(function (s) {
          setStatus(s || null); setLoading(false);
          // 一旦就绪就停轮询，并补生成二维码（地址此刻才有效）
          if (s && s.state === "ready") {
            if (pollRef.current) { clearInterval(pollRef.current); pollRef.current = null; }
            if (s.mode === "cloudflare") generatePair();
          }
        }).catch(function () { setLoading(false); });
      };

      var generatePair = function () {
        if (!props.rpcCall) return;
        Promise.resolve(props.rpcCall("pair.create", {})).then(unwrapRpc).then(function (data) {
          setPair({ loading: false, error: null, data: data });
          setRemaining(data && data.expiresIn ? data.expiresIn : 300);
        }).catch(function (e) {
          var msg = String((e && e.message) || e);
          if (msg.indexOf("unknown endpoint") >= 0) msg = makeT(currentLang())("配对服务未就绪：请重启 DSH 后再刷新本页。", "Pairing service not ready: restart DSH and refresh this page.");
          setPair({ loading: false, error: msg, data: null });
        });
      };

      React.useEffect(function () {
        refreshStatus();
        generatePair();
        // 倒计时到末期自动换新码（用户要的就是持续刷新，接受"扫到刚换掉"的概率）。
        // 10 分钟有效期（PAIR_TTL_MS），剩 30 秒换——比原来的 60 秒/剩 8 秒宽松得多。
        var timer = setInterval(function () {
          setRemaining(function (prev) {
            var next = prev - 1;
            if (next <= 30) { generatePair(); return 300; }
            return next;
          });
        }, 1000);
        // 隧道/下载还没就绪时轮询：Cloudflare 首次要下 24MB，不能让用户干等白屏。
        // 状态从 starting 变 ready 后，再补生成一次二维码（此时的地址才是隧道地址）。
        var poll = setInterval(function () {
          refreshStatus();
        }, 2000);
        pollRef.current = poll;
        return function () { clearInterval(timer); if (pollRef.current) clearInterval(pollRef.current); };
      }, []);

      var mask = new Array(status && status.pin ? status.pin.length : 8).fill("•").join("");
      var copy = function (text, field) {
        if (!text) return;
        copyText(text); setCopied(field);
        setTimeout(function () { setCopied(null); }, 1500);
      };
      var savePin = function (nextPin) {
        if (!props.rpcCall) return;
        if (!/^[A-Za-z0-9]{8,64}$/.test(nextPin)) { setActionError(makeT(currentLang())("密码需为 8-64 位英文字母或数字", "PIN must be 8–64 letters or digits")); return; }
        setBusy(true); setActionError(null);
        Promise.resolve(props.rpcCall("pin.set", { pin: nextPin })).then(unwrapRpc).then(function (s) {
          setStatus(s || status); setShowPin(true); setEditing(false); setCustomPin(""); setBusy(false);
        }).catch(function (e) { setBusy(false); setActionError(String((e && e.message) || e)); });
      };
      var refreshPin = function () {
        if (!props.rpcCall) return;
        setBusy(true); setActionError(null);
        Promise.resolve(props.rpcCall("pin.refresh", {})).then(unwrapRpc).then(function (s) {
          setStatus(s || status); setShowPin(true); setBusy(false);
        }).catch(function (e) { setBusy(false); setActionError(String((e && e.message) || e)); });
      };

      var modes = (status && status.modes) || [
        { id: "cloudflare", label: "Cloudflare" },
        { id: "lan", label: "局域网" },
        { id: "tailscale", label: "Tailscale" },
        { id: "easytier", label: "EasyTier" }
      ];
      var activeMode = (status && status.mode) || "cloudflare";
      var modeHint = activeMode === "lan"
        ? makeT(currentLang())("手机和电脑连同一个 Wi-Fi 时用这个：不经过任何服务器，速度最快也最稳。换到别的网络就连不上了。", "Use this when phone and computer share a Wi-Fi: no server involved, fastest and most stable. Won't work from other networks.")
        : activeMode === "cloudflare"
        ? makeT(currentLang())("手机不用装任何东西，扫码直接连。适合局域网/临时使用。首次会自动下载约 20MB 的 cloudflared。", "Nothing to install on the phone — just scan. Best for LAN or temporary use. First run auto-downloads cloudflared (~20MB).")
        : activeMode === "easytier"
          ? makeT(currentLang())("高级选项：电脑跑 EasyTier 组网，手机用 Shadowrocket 这类代理 App 加载下方的订阅配置（必须是「配置」模式，不能是「全局代理」，否则会拦截 Apple 证书验证导致 App 打不开）。", "Advanced: EasyTier on the computer; load the subscription below in a proxy app like Shadowrocket. Use 「Config」 mode, not global proxy — global proxy blocks Apple cert verification and the app stops launching.")
          : makeT(currentLang())("手机和电脑都要装 Tailscale：App Store（海外区）可下载，免费；两端登录同一个账号即可。适合长期、多设备使用。", "Install Tailscale on both ends — free from an overseas App Store; sign in with the same account. Best for long-term, multi-device use.");

      return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)" } },
        // 三种方式的差异说明（放在圆点上方，让用户先知道门槛再选）
        React.createElement("div", { style: { fontSize: 11, opacity: 0.65, lineHeight: 1.6, marginBottom: 8 } },
          React.createElement("div", null,
            React.createElement("b", null, "局域网"),
            makeT(currentLang())("　同一 Wi-Fi 直连，最快，不用装任何东西；换网络就用不了", "　Same Wi-Fi direct — fastest, nothing to install; won't work on other networks")),
          React.createElement("div", null,
            React.createElement("b", null, "Cloudflare"),
            makeT(currentLang())("　手机不用装东西，人在外面也能连（走公网，稍慢）", "　Nothing on the phone, works from anywhere (public relay, slower)")),
          React.createElement("div", null,
            React.createElement("b", null, "Tailscale"),
            makeT(currentLang())("　需海外 App Store 安装 Tailscale，免费；两端登录同一账号，长期更稳（推荐）", "　Install Tailscale from an overseas App Store (free); same account on both ends — most stable (recommended)")),
          React.createElement("div", null,
            React.createElement("b", null, "EasyTier"),
            makeT(currentLang())("　电脑跑 EasyTier 组网，手机端用 WireGuard 接入（需自行安装配置）", "　EasyTier on the computer; the phone joins via WireGuard (manual setup)"))),
        // 连接方式三选一（小圆点），二维码始终对应当前选中的方式
        React.createElement("div", { style: { display: "flex", gap: 16, alignItems: "center", flexWrap: "wrap", marginBottom: 6 } },
          modes.map(function (m) {
            var selected = m.id === activeMode;
            return React.createElement("label", {
              key: m.id,
              style: { display: "flex", alignItems: "center", gap: 6, cursor: busy ? "default" : "pointer", fontSize: 13, opacity: busy ? 0.5 : 1 }
            },
              React.createElement("input", {
                type: "radio", name: "pocket-conn-mode", checked: selected, disabled: busy,
                onChange: function () { if (!selected) setMode(m.id); },
                style: { accentColor: "#147A5E", margin: 0 }
              }),
              React.createElement("span", { style: { fontWeight: selected ? 600 : 400 } }, m.label));
          })),
        React.createElement("div", { style: { fontSize: 11, opacity: 0.6, marginBottom: 10, lineHeight: 1.5 } }, modeHint),
        React.createElement("div", { style: { height: 1, background: "rgba(0,0,0,.06)", margin: "10px 0" } }),
        React.createElement("div", { style: { display: "flex", gap: 14, alignItems: "flex-start", flexWrap: "wrap" } },
          remaining <= 0 && !pairValue.loading
            ? React.createElement("div", { style: { width: 148, height: 148, borderRadius: 8, border: "1px dashed rgba(0,0,0,.15)", display: "flex", flexDirection: "column", gap: 8, alignItems: "center", justifyContent: "center", fontSize: 12, flex: "0 0 148px", textAlign: "center", padding: 8 } },
                React.createElement("span", { style: { opacity: 0.6 } }, makeT(currentLang())("二维码已过期", "QR expired")),
                React.createElement("button", { type: "button", onClick: generatePair, style: chipPrimary }, makeT(currentLang())("重新生成", "Regenerate")))
            : pairValue.data && pairValue.data.qr
            ? React.createElement("img", { src: pairValue.data.qr, alt: makeT(currentLang())("扫码连接二维码", "Scan-to-connect QR"), style: { width: 148, height: 148, borderRadius: 8, background: "#fff", padding: 5, border: "1px solid rgba(0,0,0,.06)", flex: "0 0 148px" } })
            : React.createElement("div", { style: { width: 148, height: 148, borderRadius: 8, border: "1px dashed rgba(0,0,0,.15)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 12, opacity: 0.6, flex: "0 0 148px", textAlign: "center", padding: 8 } },
                pairValue.loading ? makeT(currentLang())("正在生成二维码…", "Generating QR…") : makeT(currentLang())(makeT(currentLang())("二维码不可用", "QR unavailable"), "QR unavailable")),
          React.createElement("div", { style: { flex: "1 1 220px", minWidth: 0 } },
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 2 } }, makeT(currentLang())("剩余有效时间", "Time remaining")),
            React.createElement("div", { style: { fontSize: 20, fontWeight: 600, color: remaining > 0 ? "#147A5E" : "#b45309", marginBottom: 10 } },
              remaining > 0 ? remaining + "s" : makeT(currentLang())("已过期", "Expired")),
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 2 } }, makeT(currentLang())("固定地址", "Fixed address")),
            React.createElement("div", { style: { display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginBottom: 10 } },
              React.createElement("div", { style: { fontSize: 12.5, wordBreak: "break-all", flex: "1 1 170px", minWidth: 0 } }, ((status && (status.address || status.httpsUrl))
              || (loading ? makeT(currentLang())("检测中…", "Checking…")
                : status && status.state === "starting" ? makeT(currentLang())("正在启动，稍候…", "Starting, please wait…")
                : status && status.state === "error" ? makeT(currentLang())("获取失败", "Failed")
                : makeT(currentLang())("当前方式还没有地址", "No address for this mode yet")))),
              React.createElement("button", { type: "button", onClick: function () { copy(status && (status.address || status.httpsUrl), "url"); }, style: chipStyle }, copied === "url" ? makeT(currentLang())("已复制", "Copied") : makeT(currentLang())("复制", "Copy"))),
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 4 } }, makeT(currentLang())("访问密码（手动登录用）", "Access PIN (manual login)")),
            React.createElement("div", { style: { display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap" } },
              React.createElement("code", { style: { fontSize: 13, letterSpacing: 0.5, minWidth: 68 } }, showPin ? ((status && status.pin) || "—") : mask),
              React.createElement("button", { type: "button", onClick: function () { setShowPin(!showPin); }, style: chipStyle }, showPin ? makeT(currentLang())("隐藏", "Hide") : makeT(currentLang())("显示", "Show")),
              React.createElement("button", { type: "button", onClick: function () { copy(status && status.pin, "pin"); }, style: chipStyle }, copied === "pin" ? makeT(currentLang())("已复制", "Copied") : makeT(currentLang())("复制", "Copy")),
              React.createElement("button", { type: "button", disabled: busy, onClick: refreshPin, style: chipStyle }, busy ? makeT(currentLang())("生成中…", "Generating…") : makeT(currentLang())("随机更换", "Regenerate")),
              React.createElement("button", { type: "button", disabled: busy, onClick: function () { setEditing(!editing); setActionError(null); }, style: chipStyle }, editing ? makeT(currentLang())("收起", "Collapse") : makeT(currentLang())("自定义", "Custom"))),
            editing ? React.createElement("div", { style: { display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap", marginTop: 8 } },
              React.createElement("input", {
                value: customPin, placeholder: makeT(currentLang())("8-64 位字母或数字", "8–64 letters or digits"),
                onChange: function (event) { setCustomPin(event.target.value); },
                style: { padding: "4px 8px", borderRadius: 6, border: "1px solid rgba(0,0,0,.15)", fontSize: 12, minWidth: 160 }
              }),
              React.createElement("button", { type: "button", disabled: busy, onClick: function () { savePin(customPin); }, style: chipPrimary }, makeT(currentLang())("保存", "Save")),
              React.createElement("span", { style: { fontSize: 11, opacity: 0.55 } }, makeT(currentLang())("保存后旧密码失效", "Old PIN stops working after saving"))) : null,
            // EasyTier：还没建 WireGuard 门户时，把该跑的命令直接摊出来（可复制）
            status && status.state === "needs-setup" && status.command
              ? React.createElement("div", { style: { marginTop: 10 } },
                  React.createElement("div", { style: { fontSize: 11, opacity: 0.65, lineHeight: 1.5, marginBottom: 6 } },
                    makeT(currentLang())("在电脑终端执行（需要 sudo，会创建虚拟网卡）：", "Run this in a terminal on your computer (needs sudo — it creates a virtual network interface):")),
                  React.createElement("pre", { style: { fontSize: 11, lineHeight: 1.5, background: "rgba(0,0,0,.04)", border: "1px solid rgba(0,0,0,.08)", borderRadius: 6, padding: 8, overflowX: "auto", margin: 0, whiteSpace: "pre-wrap", wordBreak: "break-all" } },
                    status.command),
                  React.createElement("div", { style: { display: "flex", gap: 8, marginTop: 6 } },
                    React.createElement("button", { type: "button", onClick: function () { copy(status.command, "cmd"); }, style: chipStyle }, copied === "cmd" ? makeT(currentLang())("已复制", "Copied") : makeT(currentLang())("复制命令", "Copy command")),
                    React.createElement("button", { type: "button", onClick: refreshStatus, style: chipStyle }, makeT(currentLang())("已执行，刷新", "Done, refresh"))))
              : null,
            // EasyTier：门户就绪后提示手机端用 WireGuard 导入
            status && status.hint
              ? React.createElement("div", { style: { fontSize: 11, color: "#147A5E", marginTop: 8, lineHeight: 1.5 } }, status.hint)
              : null,
            // 部分客户端（如 Streisand）的「扫码」只认订阅 URL，不认配置文本。
            // 给一个复制按钮，让用户直接粘贴配置，不用跟二维码较劲。
            status && status.config
              ? React.createElement("div", { style: { display: "flex", gap: 8, marginTop: 6, alignItems: "center", flexWrap: "wrap" } },
                  React.createElement("button", { type: "button", onClick: function () { copy(status.config, "wg"); }, style: chipStyle },
                    copied === "wg" ? makeT(currentLang())("已复制配置", "Config copied") : makeT(currentLang())("复制 WireGuard 配置", "Copy WireGuard config")),
                  React.createElement("span", { style: { fontSize: 11, opacity: 0.55 } },
                    makeT(currentLang())("客户端的扫码不支持时，用这个粘贴导入", "Paste this if your client's scanner won't take it")))
              : null,
            // Shadowrocket / 代理类客户端：给订阅 URL，配置里带了「10.14.14.0/24 走 SOCKS5」的规则
            status && status.confUrl
              ? React.createElement("div", { style: { marginTop: 8, paddingTop: 8, borderTop: "1px dashed rgba(0,0,0,.1)" } },
                  React.createElement("div", { style: { fontSize: 11, opacity: 0.65, marginBottom: 4 } },
                    makeT(currentLang())("用 Shadowrocket 这类代理 App：把下面这个地址填进「从 URL 下载配置」", "For proxy apps like Shadowrocket: paste this into \"download config from URL\"")),
                  React.createElement("div", { style: { display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" } },
                    React.createElement("code", { style: { fontSize: 11, wordBreak: "break-all", flex: "1 1 200px", minWidth: 0 } }, status.confUrl),
                    React.createElement("button", { type: "button", onClick: function () { copy(status.confUrl, "conf"); }, style: chipStyle },
                      copied === "conf" ? makeT(currentLang())("已复制", "Copied") : makeT(currentLang())("复制", "Copy"))),
                  React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginTop: 4, lineHeight: 1.5 } },
                    makeT(currentLang())("它会把 10.14.14.0/24 显式指向 SOCKS5，绕开代理 App 对私有网段的直连。", "It routes 10.14.14.0/24 to SOCKS5 explicitly, bypassing the app's private-subnet shortcut.")))
              : null,
            actionError ? React.createElement("div", { style: { fontSize: 11, color: "#b91c1c", marginTop: 6 } }, actionError) : null,
            (status && status.error) ? React.createElement("div", { style: { fontSize: 11, color: "#b45309", marginTop: 6, lineHeight: 1.5 } }, status.error) : null,
            pairValue.error ? React.createElement("div", { style: { fontSize: 11, color: "#b91c1c", marginTop: 6 } }, pairValue.error) : null,
            null)));
    }

    function AppDownloadCard() {
      return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)", background: "rgba(20,122,94,.04)" } },
        React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 14, alignItems: "flex-start" } },
          React.createElement("div", {
            style: { width: 116, height: 116, flex: "0 0 116px", background: "#fff", borderRadius: 8, padding: 6, border: "1px solid rgba(0,0,0,.06)", boxSizing: "border-box" },
            dangerouslySetInnerHTML: { __html: QR_SVG }
          }),
          React.createElement("div", { style: { flex: "1 1 240px", minWidth: 0 } },
            React.createElement("div", { style: { fontWeight: 600, fontSize: 15, marginBottom: 4 } }, makeT(currentLang())("在 iPhone 上使用 DSH", "Use DSH on iPhone")),
            React.createElement("div", { style: { fontSize: 12, opacity: 0.68, lineHeight: 1.55, marginBottom: 10 } },
              makeT(currentLang())("扫码从 App Store 安装 DSH Pocket iOS；装好后用上方二维码连接。", "Scan to install DSH Pocket iOS from the App Store, then connect with the QR above.")),
            React.createElement("div", { style: { display: "flex", gap: 8, flexWrap: "wrap" } },
              React.createElement("a", { href: APP_STORE_URL, target: "_blank", rel: "noreferrer", style: chipPrimary }, makeT(currentLang())("在 App Store 下载", "Download on the App Store")),
              React.createElement("a", { href: DOC_URL, target: "_blank", rel: "noreferrer", style: chipStyle }, makeT(currentLang())("使用说明", "Guide")),
              React.createElement("a", { href: REPO_URL, target: "_blank", rel: "noreferrer", style: chipStyle }, makeT(currentLang())("GitHub 仓库", "GitHub repo"))))));
    }

    function MobileAccessPanel(props) {
      return React.createElement("div", { style: { width: "100%", maxWidth: 680, display: "flex", flexDirection: "column", gap: 12 } },
        React.createElement(AppDownloadCard),
        React.createElement(AccessPanelCard, { rpcCall: props.rpcCall }));
    }

    function apply(ctx) {
      var rpcCall = function (endpoint, payload) {
        return Promise.resolve(ctx.connection.rpc.call("/dsh-pocket-ios", endpoint || "tailscale.status", payload || {}));
      };
      function MobileAccessSection() { return React.createElement(MobileAccessPanel, { rpcCall: rpcCall }); }
      ctx.slots.inject("settings.section", function () {
        return ctx.slots.register({
          name: "settings.section",
          id: "pocket-ios",
          order: 2,
          label: function () { return currentLang() === "zh" ? "手机访问（iOS）" : "Phone access (iOS)"; },
          inject: function () { return { rpcCall: rpcCall }; }
        }, MobileAccessSection);
      });
    }

    module.exports = { name: "dsh-pocket-ios", inject: ["slots", "connection"], apply: apply };
    return module.exports;
  }
});
