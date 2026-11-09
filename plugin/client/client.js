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
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        padding: "7px 12px",
        borderRadius: 999,
        fontSize: 13,
        fontWeight: 600,
        textDecoration: "none",
        color: primary ? "#fff" : "#147A5E",
        background: primary ? "#147A5E" : "rgba(20,122,94,.08)",
        border: primary ? "1px solid #147A5E" : "1px solid rgba(20,122,94,.25)"
      };
    }

    function copyText(text) {
      try {
        if (navigator.clipboard && window.isSecureContext) {
          navigator.clipboard.writeText(text);
          return true;
        }
      } catch (e) { /* 继续走兜底 */ }
      try {
        var area = document.createElement("textarea");
        area.value = text;
        area.style.position = "fixed";
        area.style.top = "-1000px";
        area.style.opacity = "0";
        document.body.appendChild(area);
        area.focus();
        area.select();
        var ok = document.execCommand("copy");
        document.body.removeChild(area);
        return ok;
      } catch (e) {
        return false;
      }
    }

    function unwrapRpc(result) {
      if (result && typeof result === "object" && "ok" in result) {
        if (!result.ok) return Promise.reject(new Error((result.error && result.error.message) || "RPC 失败"));
        return result.value !== undefined ? result.value : result;
      }
      if (result && typeof result === "object" && result.result) return unwrapRpc(result.result);
      return result;
    }

    var chipStyle = { display: "inline-flex", alignItems: "center", padding: "3px 9px", borderRadius: 999, fontSize: 12, fontWeight: 500, textDecoration: "none", color: "#147A5E", background: "rgba(20,122,94,.08)", border: "1px solid rgba(20,122,94,.22)", cursor: "pointer" };
    var chipPrimary = { ...chipStyle, color: "#fff", background: "#147A5E", border: "1px solid #147A5E" };

    function TailscaleCard(props) {
      var state = React.useState({ loading: true, error: null, status: null });
      var value = state[0];
      var setValue = state[1];
      var pinState = React.useState(false);
      var showPin = pinState[0];
      var setShowPin = pinState[1];
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

      React.useEffect(function () {
        var alive = true;
        if (!props.rpcCall) { setValue({ loading: false, error: "客户端 RPC 不可用", status: null }); return undefined; }
        Promise.resolve(props.rpcCall())
          .then(unwrapRpc)
          .then(function (status) { if (alive) setValue({ loading: false, error: null, status: status || null }); })
          .catch(function (error) { if (alive) setValue({ loading: false, error: String((error && error.message) || error), status: null }); });
        return function () { alive = false; };
      }, []);

      var copy = function (text, field) {
        if (!text) return;
        copyText(text);
        setCopied(field);
        setTimeout(function () { setCopied(null); }, 1500);
      };

      if (value.loading) {
        return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)" } },
          React.createElement("div", { style: { fontSize: 12, opacity: 0.6 } }, "正在检测 Tailscale…"));
      }
      if (value.error || !value.status) {
        return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)" } },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 14, marginBottom: 4 } }, "Tailscale 连接（可选）"),
          React.createElement("div", { style: { fontSize: 12, opacity: 0.6, lineHeight: 1.5 } }, "未读取到 Tailscale 状态；可继续使用 dsh-pocket 的局域网/公网二维码。"));
      }
      var status = value.status;
      if (!status.httpsUrl) {
        return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)" } },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 14, marginBottom: 4 } }, "Tailscale 连接（推荐，地址固定）"),
          React.createElement("div", { style: { fontSize: 12, opacity: 0.62, lineHeight: 1.55 } },
            status.available
              ? "检测到 Tailscale，但还没开启 HTTPS 代理。在 Tailscale 后台 DNS 页开启 HTTPS Certificates，然后执行 tailscale serve --bg 3081，刷新本页即可生成二维码。"
              : "未读取到 Tailscale 地址。请在 ~/.dsh/dsh-pocket-ios/tailscale.json 写入 {\"url\":\"https://你的机器.tailnet.ts.net\"}。"));
      }

      var mask = new Array(status.pin ? status.pin.length : 8).fill("•").join("");
      var savePin = function (nextPin) {
        if (!props.rpcCall) return;
        setBusy(true); setActionError(null);
        Promise.resolve(props.rpcCall("pin.set", { pin: nextPin })).then(unwrapRpc).then(function (next) {
          setValue({ loading: false, error: null, status: next });
          setShowPin(true); setEditing(false); setCustomPin(""); setBusy(false);
        }).catch(function (e) { setBusy(false); setActionError(String((e && e.message) || e)); });
      };
      var refreshPin = function () {
        if (!props.rpcCall) return;
        setBusy(true); setActionError(null);
        Promise.resolve(props.rpcCall("pin.refresh", {})).then(unwrapRpc).then(function (next) {
          setValue({ loading: false, error: null, status: next });
          setShowPin(true); setBusy(false);
        }).catch(function (e) { setBusy(false); setActionError(String((e && e.message) || e)); });
      };
      var pinRow = function () {
        return React.createElement("div", { style: { display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap" } },
          React.createElement("code", { style: { fontSize: 13, letterSpacing: 0.5, minWidth: 68 } }, showPin ? (status.pin || "—") : mask),
          React.createElement("button", { type: "button", onClick: function () { setShowPin(!showPin); }, style: chipStyle }, showPin ? "隐藏" : "显示"),
          React.createElement("button", { type: "button", onClick: function () { copy(status.pin, "pin"); }, style: chipStyle }, copied === "pin" ? "已复制" : "复制"),
          React.createElement("button", { type: "button", disabled: busy, onClick: refreshPin, style: chipStyle }, busy ? "生成中…" : "随机更换"),
          React.createElement("button", { type: "button", disabled: busy, onClick: function () { setEditing(!editing); setActionError(null); }, style: chipStyle }, editing ? "收起" : "自定义"));
      };

      return React.createElement("div", { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)" } },
        React.createElement("div", { style: { fontWeight: 600, fontSize: 14, marginBottom: 4 } }, "Tailscale 连接（推荐，地址固定且更稳定）"),
        React.createElement("div", { style: { fontSize: 12, opacity: 0.65, lineHeight: 1.5, marginBottom: 10 } },
          "手机装好 Tailscale 并开启 VPN → 扫码填入地址 → 输入下方访问密码。二维码只含地址，不含密码。"),
        React.createElement("div", { style: { display: "flex", gap: 14, alignItems: "flex-start", flexWrap: "wrap" } },
          status.qr ? React.createElement("img", { src: status.qr, alt: "Tailscale 连接二维码", style: { width: 132, height: 132, borderRadius: 8, background: "#fff", padding: 5, border: "1px solid rgba(0,0,0,.06)", flex: "0 0 132px" } }) : null,
          React.createElement("div", { style: { flex: "1 1 240px", minWidth: 0 } },
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 2 } }, "固定地址"),
            React.createElement("div", { style: { display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginBottom: 10 } },
              React.createElement("div", { style: { fontSize: 12.5, wordBreak: "break-all", flex: "1 1 180px", minWidth: 0 } }, status.httpsUrl),
              React.createElement("button", { type: "button", onClick: function () { copy(status.httpsUrl, "url"); }, style: chipStyle }, copied === "url" ? "已复制" : "复制")),
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, marginBottom: 4 } }, "访问密码"),
            pinRow(),
            editing ? React.createElement("div", { style: { display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap", marginTop: 8 } },
              React.createElement("input", {
                value: customPin, placeholder: "8-64 位字母或数字",
                onChange: function (event) { setCustomPin(event.target.value); },
                style: { padding: "4px 8px", borderRadius: 6, border: "1px solid rgba(0,0,0,.15)", fontSize: 12, minWidth: 160 }
              }),
              React.createElement("button", { type: "button", disabled: busy, onClick: function () { if (!/^[A-Za-z0-9]{8,64}$/.test(customPin)) { setActionError("密码需为 8-64 位英文字母或数字"); return; } savePin(customPin); }, style: chipPrimary }, "保存"),
              React.createElement("span", { style: { fontSize: 11, opacity: 0.55 } }, "保存后旧密码失效")) : null,
            actionError ? React.createElement("div", { style: { fontSize: 11, color: "#b91c1c", marginTop: 6 } }, actionError) : null,
            React.createElement("div", { style: { fontSize: 11, opacity: 0.55, lineHeight: 1.5, marginTop: 10 } },
              "密码只保存在本机，请勿截图分享。未开启 Tailscale 时请使用 dsh-pocket 的局域网/公网二维码。"))));
    }

    function MobileAccessPanel(props) {
      return React.createElement(
        "div",
        { style: { width: "100%", maxWidth: 680, display: "flex", flexDirection: "column", gap: 12 } },
        React.createElement(
          "div",
          { style: { padding: 14, borderRadius: 12, border: "1px solid rgba(0,0,0,.08)", background: "rgba(20,122,94,.04)" } },
          React.createElement(
            "div",
            { style: { display: "flex", flexWrap: "wrap", gap: 14, alignItems: "flex-start" } },
            React.createElement("div", {
              style: { width: 116, height: 116, flex: "0 0 116px", background: "#fff", borderRadius: 8, padding: 6, border: "1px solid rgba(0,0,0,.06)", boxSizing: "border-box" },
              dangerouslySetInnerHTML: { __html: QR_SVG }
            }),
            React.createElement(
              "div",
              { style: { flex: "1 1 240px", minWidth: 0 } },
              React.createElement("div", { style: { fontWeight: 600, fontSize: 15, marginBottom: 4 } }, "在 iPhone 上使用 DSH"),
              React.createElement("div", { style: { fontSize: 12, opacity: 0.68, lineHeight: 1.55, marginBottom: 10 } },
                "扫码从 App Store 安装 DSH Pocket iOS；装好后用下方 Tailscale 二维码连接（或 dsh-pocket 的局域网/公网二维码）。"),
              React.createElement(
                "div",
                { style: { display: "flex", gap: 8, flexWrap: "wrap" } },
                React.createElement("a", { href: APP_STORE_URL, target: "_blank", rel: "noreferrer", style: chipPrimary }, "在 App Store 下载"),
                React.createElement("a", { href: REPO_URL, target: "_blank", rel: "noreferrer", style: chipStyle }, "GitHub 仓库")
              )
            )
          )
        ),
        React.createElement(TailscaleCard, { rpcCall: props.rpcCall }),
        React.createElement("div", { style: { fontSize: 11, opacity: 0.55, lineHeight: 1.5 } },
          "局域网 / 公网二维码由 dsh-pocket 插件提供（可选安装）。Tailscale 方式无需公网暴露、地址固定，推荐优先使用。")
      );
    }

    function apply(ctx) {
      var rpcCall = function (endpoint, payload) {
        return Promise.resolve(ctx.connection.rpc.call("/dsh-pocket-ios", endpoint || "tailscale.status", payload || {}));
      };
      function MobileAccessSection() {
        return React.createElement(MobileAccessPanel, { rpcCall: rpcCall });
      }
      ctx.slots.inject("settings.section", function () {
        return ctx.slots.register(
          {
            name: "settings.section",
            id: "pocket-ios",
            order: 0,
            label: function () { return "手机访问（iOS）"; },
            inject: function () { return { rpcCall: rpcCall }; }
          },
          MobileAccessSection
        );
      });
    }

    // cordis client 插件必须导出 name 与 inject，服务才会注入（否则 ctx.slots 为 undefined）。
    module.exports = { name: "dsh-pocket-ios", inject: ["slots", "connection"], apply: apply };
    return module.exports;
  }
});
