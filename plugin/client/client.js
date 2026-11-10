window.__ModuleLoader__.load({
  id: "dsh-pocket-ios",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    var React = require("react");

    var APP_STORE_URL = "https://apps.apple.com/app/id6832288744";
    var REPO_URL = "https://github.com/jqlong17/dsh-pocket-ios";
    var QR_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100%\" height=\"100%\" viewBox=\"0 0 37 37\" shape-rendering=\"crispEdges\"><path fill=\"#ffffff\" d=\"M0 0h37v37H0z\"/><path stroke=\"#000000\" d=\"M4 4.5h7m3 0h1m4 0h5m2 0h7M4 5.5h1m5 0h1m2 0h1m7 0h1m2 0h1m1 0h1m5 0h1M4 6.5h1m1 0h3m1 0h1m1 0h1m5 0h1m1 0h1m3 0h1m1 0h1m1 0h3m1 0h1M4 7.5h1m1 0h3m1 0h1m1 0h2m7 0h1m1 0h1m2 0h1m1 0h3m1 0h1M4 8.5h1m1 0h3m1 0h1m1 0h8m2 0h3m1 0h1m1 0h3m1 0h1M4 9.5h1m5 0h1m1 0h2m1 0h5m2 0h1m1 0h1m1 0h1m5 0h1M4 10.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M12 11.5h1m1 0h1m1 0h2m1 0h2m2 0h2M4 12.5h1m1 0h5m5 0h1m1 0h2m1 0h1m1 0h1m2 0h5M8 13.5h1m5 0h2m7 0h4m1 0h1m3 0h1M5 14.5h1m3 0h2m1 0h1m1 0h3m5 0h1m1 0h1m1 0h2M4 15.5h5m6 0h2m1 0h1m1 0h1m1 0h2m1 0h2m1 0h2m1 0h1M5 16.5h3m1 0h2m1 0h2m5 0h3m5 0h1m1 0h2M4 17.5h4m3 0h3m1 0h1m1 0h2m4 0h6m3 0h1M8 18.5h3m3 0h1m2 0h4m1 0h1m2 0h1m2 0h3M5 19.5h2m2 0h1m1 0h1m3 0h1m1 0h1m1 0h1m2 0h3m3 0h1m2 0h1M4 20.5h2m2 0h1m1 0h6m2 0h1m1 0h4m3 0h1m1 0h2M4 21.5h6m1 0h1m1 0h3m5 0h3m2 0h3m1 0h1m1 0h1M4 22.5h1m4 0h3m2 0h2m3 0h3m2 0h2m2 0h1m1 0h1M4 23.5h1m2 0h3m3 0h1m1 0h2m1 0h1m5 0h2m2 0h1m2 0h1M4 24.5h1m1 0h3m1 0h1m3 0h3m4 0h1m2 0h5m1 0h3M12 25.5h3m1 0h3m2 0h2m1 0h1m3 0h5M4 26.5h7m6 0h2m3 0h3m1 0h1m1 0h3M4 27.5h1m5 0h1m1 0h6m5 0h2m3 0h1M4 28.5h1m1 0h3m1 0h1m1 0h5m1 0h1m2 0h1m2 0h5m1 0h1m1 0h1M4 29.5h1m1 0h3m1 0h1m1 0h2m8 0h1m4 0h1m1 0h2M4 30.5h1m1 0h3m1 0h1m1 0h1m1 0h1m3 0h2m3 0h2m1 0h6M4 31.5h1m5 0h1m3 0h2m3 0h1m2 0h1m1 0h2m1 0h3m1 0h1M4 32.5h7m1 0h2m1 0h1m1 0h4m1 0h2m1 0h1m2 0h1m1 0h1\"/></svg>";

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
        if (!result.ok) return Promise.reject(new Error((result.error && result.error.message) || "RPC 失败"));
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
      var remainingState = React.useState(0);
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
      var errorState = React.useState(null);
      var actionError = errorState[0];
      var setActionError = errorState[1];

      var refreshStatus = function () {
        if (!props.rpcCall) { setLoading(false); return; }
        Promise.resolve(props.rpcCall("tailscale.status", {})).then(unwrapRpc).then(function (s) {
          setStatus(s || null); setLoading(false);
        }).catch(function () { setLoading(false); });
      };

      var generatePair = function () {
        if (!props.rpcCall) return;
        Promise.resolve(props.rpcCall("pair.create", {})).then(unwrapRpc).then(function (data) {
          setPair({ loading: false, error: null, data: data });
          setRemaining(data && data.expiresIn ? data.expiresIn : 60);
        }).catch(function (e) {
          var msg = String((e && e.message) || e);
          if (msg.indexOf("unknown endpoint") >= 0) msg = "配对服务未就绪：请重启 DSH 后再刷新本页。";
          setPair({ loading: false, error: msg, data: null });
        });
      };

      React.useEffect(function () {
        refreshStatus();
        generatePair();
        var timer = setInterval(function () {
          setRemaining(function (prev) {
            var next = prev - 1;
            if (next <= 8) { generatePair(); return 60; }
            return next;
          });
        }, 1000);
        return function () { clearInterval(timer); };
      }, []);

      var mask = new Array(status && status.pin ? status.pin.length : 8).fill("•").join("");
      var copy = function (text, field) {
        if (!text) return;
        copyText(text); setCopied(field);
        setTimeout(function () { setCopied(null); }, 1500);
      };
      var savePin = function (nextPin) {
        if (!props.rpcCall) return;
        if (!/^[A-Za-z0-9]{8,64}$/.test(nextPin)) { setActionError("密码需为 8-64 位英文字母或数字"); return; }
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

      return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)" } },
        React.createElement("div", { style: { fontWeight: 600, fontSize: 14, marginBottom: 4 } }, "扫码连接（推荐，免密码）"),
        React.createElement("div", { style: { fontSize: 12, opacity: 0.65, lineHeight: 1.5, marginBottom: 10 } },
          "用 DSH Pocket 扫描下方二维码即可直接连接，无需输入密码。二维码自动轮换，每次有效 60 秒、仅可使用一次。"),
        React.createElement("div", { style: { display: "flex", gap: 14, alignItems: "flex-start", flexWrap: "wrap" } },
          pairValue.data && pairValue.data.qr
            ? React.createElement("img", { src: pairValue.data.qr, alt: "扫码连接二维码", style: { width: 148, height: 148, borderRadius: 8, background: "#fff", padding: 5, border: "1px solid rgba(0,0,0,.06)", flex: "0 0 148px" } })
            : React.createElement("div", { style: { width: 148, height: 148, borderRadius: 8, border: "1px dashed rgba(0,0,0,.15)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 12, opacity: 0.6, flex: "0 0 148px", textAlign: "center", padding: 8 } },
                pairValue.loading ? "正在生成二维码…" : "二维码不可用"),
          React.createElement("div", { style: { flex: "1 1 220px", minWidth: 0 } },
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 2 } }, "剩余有效时间"),
            React.createElement("div", { style: { fontSize: 20, fontWeight: 600, color: "#147A5E", marginBottom: 10 } }, remaining + "s"),
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 2 } }, "固定地址"),
            React.createElement("div", { style: { display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginBottom: 10 } },
              React.createElement("div", { style: { fontSize: 12.5, wordBreak: "break-all", flex: "1 1 170px", minWidth: 0 } }, status && status.httpsUrl ? status.httpsUrl : (loading ? "检测中…" : "未检测到 Tailscale 地址")),
              React.createElement("button", { type: "button", onClick: function () { copy(status && status.httpsUrl, "url"); }, style: chipStyle }, copied === "url" ? "已复制" : "复制")),
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 4 } }, "访问密码（手动登录用）"),
            React.createElement("div", { style: { display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap" } },
              React.createElement("code", { style: { fontSize: 13, letterSpacing: 0.5, minWidth: 68 } }, showPin ? ((status && status.pin) || "—") : mask),
              React.createElement("button", { type: "button", onClick: function () { setShowPin(!showPin); }, style: chipStyle }, showPin ? "隐藏" : "显示"),
              React.createElement("button", { type: "button", onClick: function () { copy(status && status.pin, "pin"); }, style: chipStyle }, copied === "pin" ? "已复制" : "复制"),
              React.createElement("button", { type: "button", disabled: busy, onClick: refreshPin, style: chipStyle }, busy ? "生成中…" : "随机更换"),
              React.createElement("button", { type: "button", disabled: busy, onClick: function () { setEditing(!editing); setActionError(null); }, style: chipStyle }, editing ? "收起" : "自定义")),
            editing ? React.createElement("div", { style: { display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap", marginTop: 8 } },
              React.createElement("input", {
                value: customPin, placeholder: "8-64 位字母或数字",
                onChange: function (event) { setCustomPin(event.target.value); },
                style: { padding: "4px 8px", borderRadius: 6, border: "1px solid rgba(0,0,0,.15)", fontSize: 12, minWidth: 160 }
              }),
              React.createElement("button", { type: "button", disabled: busy, onClick: function () { savePin(customPin); }, style: chipPrimary }, "保存"),
              React.createElement("span", { style: { fontSize: 11, opacity: 0.55 } }, "保存后旧密码失效")) : null,
            actionError ? React.createElement("div", { style: { fontSize: 11, color: "#b91c1c", marginTop: 6 } }, actionError) : null,
            pairValue.error ? React.createElement("div", { style: { fontSize: 11, color: "#b91c1c", marginTop: 6 } }, pairValue.error) : null,
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, lineHeight: 1.5, marginTop: 10 } },
              "扫配对码无需密码，最省事；手动登录时用上面的访问密码。密码只保存在本机，请勿截图分享。"))));
    }

    function AppDownloadCard() {
      return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)", background: "rgba(20,122,94,.04)" } },
        React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 14, alignItems: "flex-start" } },
          React.createElement("div", {
            style: { width: 116, height: 116, flex: "0 0 116px", background: "#fff", borderRadius: 8, padding: 6, border: "1px solid rgba(0,0,0,.06)", boxSizing: "border-box" },
            dangerouslySetInnerHTML: { __html: QR_SVG }
          }),
          React.createElement("div", { style: { flex: "1 1 240px", minWidth: 0 } },
            React.createElement("div", { style: { fontWeight: 600, fontSize: 15, marginBottom: 4 } }, "在 iPhone 上使用 DSH"),
            React.createElement("div", { style: { fontSize: 12, opacity: 0.68, lineHeight: 1.55, marginBottom: 10 } },
              "扫码从 App Store 安装 DSH Pocket iOS；装好后用上方二维码连接（或 dsh-pocket 的局域网/公网二维码）。"),
            React.createElement("div", { style: { display: "flex", gap: 8, flexWrap: "wrap" } },
              React.createElement("a", { href: APP_STORE_URL, target: "_blank", rel: "noreferrer", style: chipPrimary }, "在 App Store 下载"),
              React.createElement("a", { href: REPO_URL, target: "_blank", rel: "noreferrer", style: chipStyle }, "GitHub 仓库")))));
    }

    function MobileAccessPanel(props) {
      return React.createElement("div", { style: { width: "100%", maxWidth: 680, display: "flex", flexDirection: "column", gap: 12 } },
        React.createElement(AppDownloadCard),
        React.createElement(AccessPanelCard, { rpcCall: props.rpcCall }),
        React.createElement("div", { style: { fontSize: 11, opacity: 0.55, lineHeight: 1.5 } },
          "局域网 / 公网二维码由 dsh-pocket 插件提供（可选）。扫码配对无需密码，推荐优先使用。"));
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
          label: function () { return "手机访问（iOS）"; },
          inject: function () { return { rpcCall: rpcCall }; }
        }, MobileAccessSection);
      });
    }

    module.exports = { name: "dsh-pocket-ios", inject: ["slots", "connection"], apply: apply };
    return module.exports;
  }
});
