window.__ModuleLoader__.load({
  id: "dsh-pocket-ios",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    var React = require("react");

    var RELEASE_URL = "https://github.com/jqlong17/dsh-pocket-ios/releases/latest";
    var DOWNLOAD_URL = "https://github.com/jqlong17/dsh-pocket-ios/releases/latest/download/DSHPocket.ipa";
    var QR_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"200\" viewBox=\"0 0 33 33\" shape-rendering=\"crispEdges\"><path fill=\"#ffffff\" d=\"M0 0h33v33H0z\"/><path stroke=\"#000000\" d=\"M0 0.5h7m2 0h1m3 0h2m1 0h6m1 0h1m2 0h7M0 1.5h1m5 0h1m2 0h1m2 0h4m4 0h3m3 0h1m5 0h1M0 2.5h1m1 0h3m1 0h1m1 0h4m1 0h1m1 0h2m1 0h1m2 0h2m3 0h1m1 0h3m1 0h1M0 3.5h1m1 0h3m1 0h1m1 0h1m5 0h4m4 0h1m1 0h1m1 0h1m1 0h3m1 0h1M0 4.5h1m1 0h3m1 0h1m1 0h1m2 0h2m2 0h1m1 0h5m1 0h1m2 0h1m1 0h3m1 0h1M0 5.5h1m5 0h1m1 0h1m2 0h1m1 0h1m1 0h2m3 0h1m3 0h1m1 0h1m5 0h1M0 6.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M8 7.5h5m1 0h2m2 0h4m1 0h2M0 8.5h1m1 0h5m2 0h1m2 0h4m1 0h1m1 0h2m5 0h5M7 9.5h1m1 0h1m6 0h1m1 0h3m2 0h1m2 0h2m1 0h2m1 0h1M2 10.5h8m5 0h2m1 0h1m2 0h2m1 0h3m1 0h1m1 0h2M2 11.5h2m1 0h1m2 0h1m1 0h1m3 0h1m1 0h1m2 0h1m1 0h1m2 0h2m2 0h3M0 12.5h1m1 0h2m1 0h7m5 0h1m1 0h1m2 0h2m1 0h1m1 0h3M1 13.5h5m4 0h2m2 0h4m1 0h1m3 0h1m2 0h2m1 0h1m1 0h2M1 14.5h3m1 0h2m1 0h1m1 0h1m2 0h1m3 0h1m2 0h1m1 0h1m2 0h3m1 0h1m1 0h1M4 15.5h2m7 0h2m1 0h1m2 0h1m1 0h1m1 0h1m1 0h2m2 0h2M0 16.5h3m1 0h1m1 0h1m2 0h4m1 0h1m2 0h1m4 0h4m1 0h2m3 0h1M3 17.5h3m6 0h3m3 0h4m1 0h1m2 0h2m1 0h4M5 18.5h2m1 0h3m2 0h1m1 0h2m3 0h3m1 0h1m1 0h3m1 0h2M0 19.5h1m4 0h1m1 0h1m3 0h2m1 0h1m1 0h1m1 0h5m2 0h1m1 0h5M2 20.5h2m1 0h2m3 0h1m1 0h1m2 0h1m1 0h1m1 0h2m1 0h1m1 0h2m2 0h2m1 0h2M0 21.5h5m3 0h6m1 0h1m1 0h5m1 0h2m1 0h1m3 0h1m1 0h1M0 22.5h1m1 0h1m2 0h3m1 0h1m3 0h1m1 0h1m1 0h1m2 0h1m4 0h1m3 0h1m1 0h1M0 23.5h1m1 0h1m2 0h1m1 0h2m1 0h2m1 0h4m1 0h1m1 0h7m2 0h2m1 0h1M0 24.5h1m2 0h6m3 0h6m4 0h1m1 0h5m3 0h1M8 25.5h5m5 0h2m1 0h1m1 0h2m3 0h1m1 0h1m1 0h1M0 26.5h7m3 0h1m1 0h5m3 0h2m1 0h2m1 0h1m1 0h1m1 0h1M0 27.5h1m5 0h1m1 0h1m3 0h4m4 0h5m3 0h3M0 28.5h1m1 0h3m1 0h1m1 0h3m4 0h3m1 0h1m2 0h1m1 0h6m2 0h1M0 29.5h1m1 0h3m1 0h1m1 0h2m1 0h2m3 0h1m2 0h2m1 0h4m2 0h1m2 0h2M0 30.5h1m1 0h3m1 0h1m1 0h1m2 0h1m2 0h4m2 0h1m1 0h1m3 0h2m1 0h1M0 31.5h1m5 0h1m2 0h4m1 0h1m4 0h1m1 0h3m1 0h2m1 0h3M0 32.5h7m1 0h4m3 0h4m3 0h6m3 0h1\"/></svg>\n";
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
        { style: { display: "flex", gap: 18, alignItems: "flex-start", padding: 16, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)", background: "rgba(20,122,94,.04)", marginBottom: 18 } },
        React.createElement("div", {
          style: { width: 132, height: 132, flex: "0 0 132px", background: "#fff", borderRadius: 10, padding: 8, border: "1px solid rgba(0,0,0,.06)", boxSizing: "border-box" },
          dangerouslySetInnerHTML: { __html: QR_SVG }
        }),
        React.createElement(
          "div",
          { style: { flex: 1, minWidth: 0 } },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 15, marginBottom: 6 } }, "在 iPhone 上使用 DSH"),
          React.createElement(
            "div",
            { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.6, marginBottom: 10 } },
            "用手机扫描二维码打开 DSH Pocket iOS 的最新 Release，下载 IPA 后用 AltStore / Sideloadly 自签安装（也可以直接下载下方 IPA）。装好后在 App 里扫描电脑上 dsh-pocket 的二维码即可连接本机 DSH。"
          ),
          React.createElement(
            "div",
            { style: { display: "flex", gap: 10, flexWrap: "wrap" } },
            React.createElement("a", { href: RELEASE_URL, target: "_blank", rel: "noreferrer", style: linkStyle(true) }, "打开 Release 页面"),
            React.createElement("a", { href: DOWNLOAD_URL, target: "_blank", rel: "noreferrer", style: linkStyle(false) }, "直接下载 IPA")
          )
        )
      );
    }

    var CARD_HTML =
      '<div style="display:flex;gap:16px;align-items:flex-start;padding:16px;border-radius:14px;border:1px solid rgba(0,0,0,.08);background:rgba(20,122,94,.04);margin:0 0 16px 0;text-align:left">' +
        '<div style="width:120px;height:120px;flex:0 0 120px;background:#fff;border-radius:10px;padding:6px;border:1px solid rgba(0,0,0,.06);box-sizing:border-box">' + QR_SVG + "</div>" +
        '<div style="flex:1;min-width:0">' +
          '<div style="font-weight:600;font-size:15px;margin-bottom:6px">在 iPhone 上使用 DSH</div>' +
          '<div style="font-size:13px;opacity:.72;line-height:1.6;margin-bottom:10px">扫码打开 DSH Pocket iOS 的最新 Release，下载 IPA 后自签安装；装好后在 App 里扫描上方二维码连接本机 DSH。</div>' +
          '<div style="display:flex;gap:10px;flex-wrap:wrap">' +
            '<a href="' + RELEASE_URL + '" target="_blank" rel="noreferrer" style="display:inline-flex;align-items:center;padding:7px 12px;border-radius:999px;font-size:13px;font-weight:600;text-decoration:none;color:#fff;background:#147A5E">打开 Release 页面</a>' +
            '<a href="' + DOWNLOAD_URL + '" target="_blank" rel="noreferrer" style="display:inline-flex;align-items:center;padding:7px 12px;border-radius:999px;font-size:13px;font-weight:600;text-decoration:none;color:#147A5E;background:rgba(20,122,94,.08);border:1px solid rgba(20,122,94,.25)">直接下载源码 zip</a>' +
          "</div>" +
        "</div>" +
      "</div>";

    /** 尽力把卡片插到「手机访问 → 局域网访问」上方；失败时不影响原生设置入口。 */
    function insertCardInPocketPage() {
      if (typeof document === "undefined") return;
      if (document.getElementById(CARD_ID)) return;
      var nodes = Array.prototype.slice.call(document.querySelectorAll("div,span,p"));
      var label = null;
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.childElementCount === 0 && (el.textContent || "").trim() === "局域网访问" && el.offsetParent !== null) { label = el; break; }
      }
      if (!label) return;
      var container = label.parentElement;
      for (var depth = 0; depth < 6 && container; depth++) {
        if (container.querySelector("img,canvas,svg")) {
          var card = document.createElement("div");
          card.id = CARD_ID;
          card.innerHTML = CARD_HTML;
          container.insertBefore(card, container.firstChild);
          return;
        }
        container = container.parentElement;
      }
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
      try {
        ctx.slots.inject("settings.section", function () {
          return ctx.slots.register(
            { name: "settings.section", id: "pocket-ios", order: 0, label: function () { return "iOS 客户端"; } },
            IOSCard
          );
        });
      } catch (e) {}
      startObserver();
    }

    module.exports = { apply: apply };
    return module.exports;
  }
});
