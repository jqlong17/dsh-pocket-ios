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

    function unwrapRpc(result) {
      if (result && typeof result === "object" && "ok" in result) {
        if (!result.ok) return Promise.reject(new Error((result.error && result.error.message) || "RPC 失败"));
        return result.value !== undefined ? result.value : result;
      }
      if (result && typeof result === "object" && result.result) return unwrapRpc(result.result);
      return result;
    }

    function TailscaleCard(props) {
      var state = React.useState({ loading: true, error: null, status: null });
      var value = state[0];
      var setValue = state[1];
      React.useEffect(function () {
        var alive = true;
        if (!props.rpcCall) {
          setValue({ loading: false, error: "客户端 RPC 不可用", status: null });
          return undefined;
        }
        Promise.resolve(props.rpcCall())
          .then(unwrapRpc)
          .then(function (status) { if (alive) setValue({ loading: false, error: null, status: status || null }); })
          .catch(function (error) { if (alive) setValue({ loading: false, error: String((error && error.message) || error), status: null }); });
        return function () { alive = false; };
      }, []);

      if (value.loading) {
        return React.createElement("div", { style: { padding: 18, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)" } },
          React.createElement("div", { style: { fontSize: 13, opacity: 0.65 } }, "正在检测 Tailscale…"));
      }
      if (value.error || !value.status) {
        return React.createElement("div", { style: { padding: 18, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)" } },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 16, marginBottom: 8 } }, "Tailscale 连接（可选）"),
          React.createElement("div", { style: { fontSize: 12, opacity: 0.62, lineHeight: 1.6 } }, "未读取到 Tailscale 状态；可继续使用 dsh-pocket 的局域网/公网二维码。"));
      }
      var status = value.status;
      if (!status.httpsUrl) {
        return React.createElement("div", { style: { padding: 18, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)" } },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 16, marginBottom: 8 } }, "Tailscale 连接（推荐，地址固定且更稳定）"),
          React.createElement("div", { style: { fontSize: 12, opacity: 0.65, lineHeight: 1.65 } },
            status.available
              ? "检测到 Tailscale，但还没开启 HTTPS 代理。在 Tailscale 后台 DNS 页开启 HTTPS Certificates，然后执行 "
              : "未读取到 Tailscale 地址。可在 ~/.dsh/dsh-pocket-ios/tailscale.json 写入 {\"url\":\"https://你的机器.tailnet.ts.net\"}（插件优先读取该配置）。",
            status.available ? React.createElement("code", null, "tailscale serve --bg 3081") : null,
            status.available ? "，刷新本页即可生成二维码。" : ""));
      }
      var copy = function () { try { navigator.clipboard.writeText(status.httpsUrl); } catch (e) {} };
      return React.createElement("div", { style: { padding: 18, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)" } },
        React.createElement("div", { style: { fontWeight: 600, fontSize: 16, marginBottom: 8 } }, "Tailscale 连接（推荐，地址固定且更稳定）"),
        React.createElement("div", { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.65, marginBottom: 12 } },
          "手机装好 Tailscale（同一账号、开启 VPN）后，用 DSH Pocket 扫下面的二维码即可连接：二维码里已包含地址与访问密码，扫完自动连接。换 Wi‑Fi / 切 4G 都不用重新扫码。"),
        React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" } },
          status.qr ? React.createElement("img", { src: status.qr, alt: "Tailscale 连接二维码", style: { width: 158, height: 158, borderRadius: 10, background: "#fff", padding: 6, border: "1px solid rgba(0,0,0,.06)" } }) : null,
          React.createElement("div", { style: { flex: "1 1 220px", minWidth: 0 } },
            React.createElement("div", { style: { fontSize: 12, opacity: 0.6, marginBottom: 4 } }, "固定地址"),
            React.createElement("div", { style: { fontSize: 13, wordBreak: "break-all", marginBottom: 10 } }, status.httpsUrl),
            React.createElement("button", { type: "button", onClick: copy, style: linkStyle(false) }, "复制地址"),
            React.createElement("div", { style: { fontSize: 12, opacity: 0.6, marginTop: 10, lineHeight: 1.6 } },
              "如果二维码里没有密码，也可以手动输入访问密码；未安装 Tailscale 时请使用 dsh-pocket 的局域网/公网二维码。"))));
    }

    function MobileAccessPanel(props) {
      return React.createElement(
        "div",
        { style: { width: "100%", maxWidth: 760, display: "flex", flexDirection: "column", gap: 16 } },
        React.createElement(
          "div",
          { style: { padding: 18, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)", background: "rgba(20,122,94,.04)" } },
          React.createElement(
            "div",
            { style: { display: "flex", flexWrap: "wrap", gap: 18, alignItems: "flex-start" } },
            React.createElement("div", {
              style: { width: 132, height: 132, flex: "0 0 132px", background: "#fff", borderRadius: 10, padding: 8, border: "1px solid rgba(0,0,0,.06)", boxSizing: "border-box" },
              dangerouslySetInnerHTML: { __html: QR_SVG }
            }),
            React.createElement(
              "div",
              { style: { flex: "1 1 240px", minWidth: 0 } },
              React.createElement("div", { style: { fontWeight: 600, fontSize: 16, marginBottom: 6 } }, "在 iPhone 上使用 DSH"),
              React.createElement("div", { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.65, marginBottom: 12 } },
                "用手机扫描二维码从 App Store 安装 DSH Pocket iOS。装好后在本页下方扫描 Tailscale 二维码（或 dsh-pocket 的局域网/公网二维码）即可连接。"),
              React.createElement(
                "div",
                { style: { display: "flex", gap: 10, flexWrap: "wrap" } },
                React.createElement("a", { href: APP_STORE_URL, target: "_blank", rel: "noreferrer", style: linkStyle(true) }, "在 App Store 下载"),
                React.createElement("a", { href: REPO_URL, target: "_blank", rel: "noreferrer", style: linkStyle(false) }, "GitHub 仓库")
              )
            )
          )
        ),
        React.createElement(TailscaleCard, { rpcCall: props.rpcCall }),
        React.createElement("div", { style: { fontSize: 12, opacity: 0.6, lineHeight: 1.6 } },
          "局域网 / 公网二维码由 dsh-pocket 插件提供（可选安装）。Tailscale 方式无需公网暴露、地址固定，推荐优先使用。")
      );
    }

    function apply(ctx) {
      var rpcCall = function () {
        return Promise.resolve(ctx.connection.rpc.call("/dsh-pocket-ios", "tailscale.status", {}));
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
