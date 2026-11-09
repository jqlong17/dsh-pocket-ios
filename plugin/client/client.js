window.__ModuleLoader__.load({
  id: "dsh-pocket-ios",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    var React = require("react");

    var APP_STORE_URL = "https://apps.apple.com/app/id6832288744";
    var REPO_URL = "https://github.com/jqlong17/dsh-pocket-ios";
    var QR_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100%\" height=\"100%\" viewBox=\"0 0 37 37\" shape-rendering=\"crispEdges\"><path fill=\"#ffffff\" d=\"M0 0h37v37H0z\"/><path stroke=\"#000000\" d=\"M4 4.5h7m3 0h1m4 0h5m2 0h7M4 5.5h1m5 0h1m2 0h1m7 0h1m2 0h1m1 0h1m5 0h1M4 6.5h1m1 0h3m1 0h1m1 0h1m5 0h1m1 0h1m3 0h1m1 0h1m1 0h3m1 0h1M4 7.5h1m1 0h3m1 0h1m1 0h2m7 0h1m1 0h1m2 0h1m1 0h3m1 0h1M4 8.5h1m1 0h3m1 0h1m1 0h8m2 0h3m1 0h1m1 0h3m1 0h1M4 9.5h1m5 0h1m1 0h2m1 0h5m2 0h1m1 0h1m1 0h1m5 0h1M4 10.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M12 11.5h1m1 0h1m1 0h2m1 0h2m2 0h2M4 12.5h1m1 0h5m5 0h1m1 0h2m1 0h1m1 0h1m2 0h5M8 13.5h1m5 0h2m7 0h4m1 0h1m3 0h1M5 14.5h1m3 0h2m1 0h1m1 0h3m5 0h1m1 0h1m1 0h2M4 15.5h5m6 0h2m1 0h1m1 0h1m1 0h2m1 0h2m1 0h2m1 0h1M5 16.5h3m1 0h2m1 0h2m5 0h3m5 0h1m1 0h2M4 17.5h4m3 0h3m1 0h1m1 0h2m4 0h6m3 0h1M8 18.5h3m3 0h1m2 0h4m1 0h1m2 0h1m2 0h3M5 19.5h2m2 0h1m1 0h1m3 0h1m1 0h1m1 0h1m2 0h3m3 0h1m2 0h1M4 20.5h2m2 0h1m1 0h6m2 0h1m1 0h4m3 0h1m1 0h2M4 21.5h6m1 0h1m1 0h3m5 0h3m2 0h3m1 0h1m1 0h1M4 22.5h1m4 0h3m2 0h2m3 0h3m2 0h2m2 0h1m1 0h1M4 23.5h1m2 0h3m3 0h1m1 0h2m1 0h1m5 0h2m2 0h1m2 0h1M4 24.5h1m1 0h3m1 0h1m3 0h3m4 0h1m2 0h5m1 0h3M12 25.5h3m1 0h3m2 0h2m1 0h1m3 0h5M4 26.5h7m6 0h2m3 0h3m1 0h1m1 0h3M4 27.5h1m5 0h1m1 0h6m5 0h2m3 0h1M4 28.5h1m1 0h3m1 0h1m1 0h5m1 0h1m2 0h1m2 0h5m1 0h1m1 0h1M4 29.5h1m1 0h3m1 0h1m1 0h2m8 0h1m4 0h1m1 0h2M4 30.5h1m1 0h3m1 0h1m1 0h1m1 0h1m3 0h2m3 0h2m1 0h6M4 31.5h1m5 0h1m3 0h2m3 0h1m2 0h1m1 0h2m1 0h3m1 0h1M4 32.5h7m1 0h2m1 0h1m1 0h4m1 0h2m1 0h1m2 0h1m1 0h1\"/></svg>";

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
        if (!props.rpcCall) { setValue({ loading: false, error: "客户端 RPC 不可用", status: null }); return undefined; }
        Promise.resolve(props.rpcCall())
          .then(unwrapRpc)
          .then(function (status) { if (alive) setValue({ loading: false, error: null, status: status || null }); })
          .catch(function (error) { if (alive) setValue({ loading: false, error: String((error && error.message) || error), status: null }); });
        return function () { alive = false; };
      }, []);

      var box = { marginTop: 14, paddingTop: 14, borderTop: "1px solid rgba(0,0,0,.08)" };
      if (value.loading) {
        return React.createElement("div", { style: box }, React.createElement("div", { style: { fontSize: 13, opacity: 0.72 } }, "正在检测 Tailscale…"));
      }
      if (value.error || !value.status) {
        return React.createElement("div", { style: box },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 14, marginBottom: 6 } }, "Tailscale 连接（可选）"),
          React.createElement("div", { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.6 } }, "未读取到 Tailscale 状态；可继续使用局域网/公网二维码。"));
      }
      var status = value.status;
      if (!status.httpsUrl) {
        return React.createElement("div", { style: box },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 14, marginBottom: 6 } }, "Tailscale 连接（推荐，地址固定）"),
          React.createElement("div", { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.6 } },
            "检测到 Tailscale，但还没开启 HTTPS 代理。在 Tailscale 后台 DNS 页开启 HTTPS Certificates，然后在终端执行 ",
            React.createElement("code", null, "tailscale serve --bg 3081"),
            "，刷新本页即可生成二维码。"));
      }
      var copy = function () { try { navigator.clipboard.writeText(status.httpsUrl); } catch (e) {} };
      return React.createElement("div", { style: box },
        React.createElement("div", { style: { fontWeight: 600, fontSize: 14, marginBottom: 6 } }, "Tailscale 连接（推荐，地址固定且更稳定）"),
        React.createElement("div", { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.6, marginBottom: 10 } },
          "手机装好 Tailscale 并开启 VPN 后，用 DSH Pocket 扫下面的二维码即可连接：二维码里已包含地址与访问密码，扫完自动连接。换 Wi‑Fi / 切 4G 都不用重新扫码。"),
        React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" } },
          status.qr ? React.createElement("img", { src: status.qr, alt: "Tailscale 连接二维码", style: { width: 150, height: 150, borderRadius: 10, background: "#fff", padding: 6, border: "1px solid rgba(0,0,0,.06)" } }) : null,
          React.createElement("div", { style: { flex: "1 1 220px", minWidth: 0 } },
            React.createElement("div", { style: { fontSize: 12, opacity: 0.6, marginBottom: 4 } }, "固定地址"),
            React.createElement("div", { style: { fontSize: 13, wordBreak: "break-all", marginBottom: 10 } }, status.httpsUrl),
            React.createElement("button", { type: "button", onClick: copy, style: linkStyle(false) }, "复制地址"),
            React.createElement("div", { style: { fontSize: 12, opacity: 0.6, marginTop: 10, lineHeight: 1.6 } },
              "如果二维码里没有密码，也可以手动输入访问密码；未安装 Tailscale 时请使用下方局域网/公网二维码。"))));
    }

    var CARD_ID = "dsh-pocket-ios-card";

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

    function IOSCard() {
      return React.createElement(
        "div",
        { style: { display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start", padding: 16, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)", background: "rgba(20,122,94,.04)", marginBottom: 18, boxSizing: "border-box", width: "100%", maxWidth: 620 } },
        React.createElement("div", {
          style: { width: 120, height: 120, flex: "0 0 120px", background: "#fff", borderRadius: 10, padding: 8, border: "1px solid rgba(0,0,0,.06)", boxSizing: "border-box" },
          dangerouslySetInnerHTML: { __html: QR_SVG }
        }),
        React.createElement(
          "div",
          { style: { flex: "1 1 220px", minWidth: 0 } },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 15, marginBottom: 6 } }, "在 iPhone 上使用 DSH"),
          React.createElement(
            "div",
            { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.6, marginBottom: 10 } },
            "用手机扫描二维码从 App Store 安装 DSH Pocket iOS。装好后在 App 里扫描电脑上 dsh-pocket 的二维码即可连接本机 DSH。"
          ),
          React.createElement(
            "div",
            { style: { display: "flex", gap: 10, flexWrap: "wrap" } },
            React.createElement("a", { href: APP_STORE_URL, target: "_blank", rel: "noreferrer", style: linkStyle(true) }, "在 App Store 下载"),
            React.createElement("a", { href: REPO_URL, target: "_blank", rel: "noreferrer", style: linkStyle(false) }, "GitHub 仓库")
          )
        )
      );
    }

    var CARD_HTML =
      '<div style="box-sizing:border-box;width:100%;max-width:620px;display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start;padding:16px;border-radius:14px;border:1px solid rgba(0,0,0,.08);background:rgba(20,122,94,.04);margin:0 0 16px 0;text-align:left">' +
        '<div style="box-sizing:border-box;width:110px;height:110px;flex:0 0 110px;background:#fff;border-radius:10px;padding:6px;border:1px solid rgba(0,0,0,.06)">' + QR_SVG + "</div>" +
        '<div style="flex:1 1 220px;min-width:0">' +
          '<div style="font-weight:600;font-size:15px;margin-bottom:6px">在 iPhone 上使用 DSH</div>' +
          '<div style="font-size:13px;opacity:.72;line-height:1.6;margin-bottom:10px">扫码从 App Store 安装 DSH Pocket iOS。装好后在 App 里扫描电脑上 dsh-pocket 的二维码即可连接本机 DSH。</div>' +
          '<div style="display:flex;gap:10px;flex-wrap:wrap">' +
            '<a href="' + APP_STORE_URL + '" target="_blank" rel="noreferrer" style="display:inline-flex;align-items:center;padding:7px 12px;border-radius:999px;font-size:13px;font-weight:600;text-decoration:none;color:#fff;background:#147A5E">在 App Store 下载</a>' +
            '<a href="' + REPO_URL + '" target="_blank" rel="noreferrer" style="display:inline-flex;align-items:center;padding:7px 12px;border-radius:999px;font-size:13px;font-weight:600;text-decoration:none;color:#147A5E;background:rgba(20,122,94,.08);border:1px solid rgba(20,122,94,.25)">GitHub 仓库</a>' +
          "</div>" +
        "</div>" +
      "</div>";

    /** 把 Tailscale 二维码注入「手机访问」卡片（同源 fetch，走插件 RPC 路由）。 */
    function loadTailscaleIntoCard(card) {
      if (!card || card.querySelector("[data-tailscale-block]")) return;
      var wrap = document.createElement("div");
      wrap.setAttribute("data-tailscale-block", "1");
      wrap.style.cssText = "margin-top:14px;padding-top:14px;border-top:1px solid rgba(0,0,0,.08);width:100%";
      wrap.innerHTML = '<div style="font-size:13px;opacity:.65">正在检测 Tailscale…</div>';
      card.appendChild(wrap);
      var rpcId = "ts-" + Math.random().toString(36).slice(2);
      fetch("/dsh-pocket-ios/tailscale.status", {
        method: "POST",
        credentials: "include",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ rpcId: rpcId, method: "tailscale.status", payload: {} })
      }).then(function (r) { return r.json(); }).then(function (json) {
        var result = json && json.result;
        var value = result && result.ok ? result.value : null;
        if (!value) throw new Error("no status");
        if (!value.httpsUrl) {
          wrap.innerHTML =
            '<div style="font-weight:600;font-size:14px;margin-bottom:6px">Tailscale 连接（推荐，地址固定）</div>' +
            '<div style="font-size:12px;opacity:.65;line-height:1.6">检测到 Tailscale，但还没开启 HTTPS 代理。在 Tailscale 后台 DNS 页开启 HTTPS Certificates，然后执行 <code>tailscale serve --bg 3081</code>，刷新本页即可生成二维码。</div>';
          return;
        }
        wrap.innerHTML =
          '<div style="font-weight:600;font-size:14px;margin-bottom:8px">Tailscale 连接（推荐，地址固定且更稳定）</div>' +
          '<div style="display:flex;flex-wrap:wrap;gap:14px;align-items:flex-start">' +
            (value.qr ? '<img alt="Tailscale 连接二维码" src="' + value.qr + '" style="width:150px;height:150px;border-radius:10px;background:#fff;padding:6px;border:1px solid rgba(0,0,0,.06);box-sizing:border-box" />' : '') +
            '<div style="flex:1 1 200px;min-width:0">' +
              '<div style="font-size:12px;opacity:.6;margin-bottom:4px">固定地址</div>' +
              '<div style="font-size:13px;word-break:break-all;margin-bottom:8px">' + value.httpsUrl + '</div>' +
              '<div style="font-size:12px;opacity:.65;line-height:1.6">手机装好 Tailscale（同一账号、开启 VPN）后，用 DSH Pocket 扫左侧二维码：已包含地址与访问密码，扫完自动连接，换 Wi-Fi / 切 4G 都不用重扫。</div>' +
            '</div>' +
          '</div>';
      }).catch(function () {
        wrap.innerHTML = '<div style="font-size:12px;opacity:.6">未读取到 Tailscale 状态；可继续使用局域网/公网二维码。</div>';
      });
    }

    /** 把卡片插到「手机访问」页签内容内（切到其他页签时移除），失败不影响原生入口。 */
    function insertCardInPocketPage() {
      if (typeof document === "undefined") return;
      var nodes = Array.prototype.slice.call(document.querySelectorAll("div,span,p"));
      var label = null;
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.childElementCount === 0 && (el.textContent || "").trim() === "局域网访问" && el.offsetParent !== null) { label = el; break; }
      }
      if (!label) {
        // 当前不在「手机访问」页签：删掉已插入的卡片，避免它出现在别的 tab。
        var stale = document.getElementById(CARD_ID);
        if (stale) stale.parentNode.removeChild(stale);
        return;
      }
      if (document.getElementById(CARD_ID)) return;
      // 从标签向上找到「页签内容根」：父级是滚动容器的那个节点。
      // 卡片作为页签内容的子节点插入，切走时随内容一起被 React 卸载。
      var node = label;
      var contentRoot = null;
      for (var depth = 0; depth < 10 && node && node !== document.body; depth++) {
        var parent = node.parentElement;
        if (!parent) break;
        var style = window.getComputedStyle(parent);
        var scrollable = style.overflowY === "auto" || style.overflowY === "scroll";
        if (scrollable) { contentRoot = node; break; }
        node = parent;
      }
      if (!contentRoot) return;
      var card = document.createElement("div");
      card.id = CARD_ID;
      card.innerHTML = CARD_HTML;
      contentRoot.insertBefore(card, contentRoot.firstChild);
      loadTailscaleIntoCard(card);
    }

    var observer = null;
    function startObserver() {
      if (typeof document === "undefined" || typeof MutationObserver === "undefined" || observer) return;
      var run = function () { try { insertCardInPocketPage(); } catch (e) {} };
      observer = new MutationObserver(run);
      observer.observe(document.body, { childList: true, subtree: true });
      run();
    }

    function apply(ctx) {
      var rpcCall = function () {
        try {
          return Promise.resolve(ctx.connection.rpc.call("/dsh-pocket-ios", "tailscale.status", {}));
        } catch (error) {
          return Promise.reject(error);
        }
      };
      function IOSSection() {
        return React.createElement(
          "div",
          { style: { width: "100%" } },
          React.createElement(IOSCard),
          React.createElement(TailscaleCard, { rpcCall: rpcCall })
        );
      }
      try {
        ctx.slots.inject("settings.section", function () {
          return ctx.slots.register(
            { name: "settings.section", id: "pocket-ios", order: 0, label: function () { return "iOS 客户端"; } },
            IOSSection
          );
        });
      } catch (e) {}
      startObserver();
    }

    module.exports = { apply: apply };
    return module.exports;
  }
});
