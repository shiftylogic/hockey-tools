"use strict";

(function() {
    let tb = {
        b: null,
        v: window.matchMedia("(prefers-color-scheme:dark)").matches ? "dark" : "light",
        change(v) {
            this.v = v;
            let t = v == "dark" ? "Turn off dark mode" : "Turn on dark mode";
            document.querySelector("html").setAttribute("data-theme", v);
            this.b.innerHTML = "<i>"+t+"</i>";
            this.b.setAttribute("aria-label", t);
        },
        init() {
            this.b = document.createElement("button");
            this.b.className = "contrast switcher";
            this.b.addEventListener("click", () => {
                this.change(this.v == "dark" ? "light" : "dark");
            });
            document.querySelector("body").appendChild(this.b);
        },
    };

    tb.init();
    tb.change(tb.v);
})();
