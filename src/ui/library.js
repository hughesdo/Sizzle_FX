// Effects library panel: search, category chips, draggable cards.
import { catColor } from "../timeline/timeline.js";

export class Library {
  constructor({ root, onAdd, onHover }) {
    this.root = root; this.onAdd = onAdd; this.onHover = onHover;
    this.effects = []; this.cat = "All"; this.q = "";
    root.innerHTML = `
      <div class="lib-head">
        <span class="lib-title">effects</span><span class="lib-count" data-k="count"></span>
      </div>
      <input class="lib-search" data-k="search" placeholder="search effects…" spellcheck="false">
      <div class="lib-cats" data-k="cats"></div>
      <div class="lib-list" data-k="list"></div>
      <div class="lib-desc" data-k="desc">drag onto a lane, or double-click to add at the playhead</div>`;
    this.el = {};
    root.querySelectorAll("[data-k]").forEach((e) => (this.el[e.dataset.k] = e));
    this.el.search.addEventListener("input", () => { this.q = this.el.search.value.trim().toLowerCase(); this.renderList(); });
  }

  setEffects(list) { this.effects = list; this.renderCats(); this.renderList(); }

  // thumbnail for one effect (rendered from the user's own video by ThumbMaker)
  setThumb(id, url) {
    this.thumbs = this.thumbs || new Map();
    this.thumbs.set(id, url);
    const img = this.el.list.querySelector(`.fx-card[data-id="${CSS.escape(id)}"] .fx-thumb`);
    if (img) { img.style.backgroundImage = `url("${url}")`; img.classList.add("on"); }
  }
  clearThumbs() { this.thumbs = new Map(); this.el.list.querySelectorAll(".fx-thumb").forEach((t) => { t.style.backgroundImage = ""; t.classList.remove("on"); }); }

  renderCats() {
    const cats = ["All", ...new Set(this.effects.map((e) => e.category))];
    if (!cats.includes(this.cat)) this.cat = "All";
    this.el.cats.innerHTML = "";
    for (const c of cats) {
      const b = document.createElement("button");
      b.className = "lib-cat" + (c === this.cat ? " on" : "");
      b.textContent = c;
      if (c !== "All") b.style.setProperty("--c", catColor(c));
      b.onclick = () => { this.cat = c; this.renderCats(); this.renderList(); };
      this.el.cats.appendChild(b);
    }
  }

  renderList() {
    const { list, count } = this.el;
    list.innerHTML = "";
    const q = this.q;
    const shown = this.effects.filter((e) => (this.cat === "All" || e.category === this.cat) &&
      (!q || e.name.toLowerCase().includes(q) || e.tags.some((t) => t.toLowerCase().includes(q)) || e.category.toLowerCase().includes(q)));
    count.textContent = `${shown.length}/${this.effects.length}`;
    for (const e of shown) {
      const card = document.createElement("div");
      card.className = "fx-card"; card.draggable = true; card.dataset.id = e.id;
      card.style.setProperty("--c", catColor(e.category));
      const badges = [e.audio ? `<span class="b-a" title="audio reactive">♪</span>` : "",
        e.needsMask ? `<span class="b-m" title="uses the subject mask">◐</span>` : "",
        e.needsHistory ? `<span class="b-h" title="uses previous frames">⧗</span>` : "",
        e.kind === "overlay" ? `<span class="b-o" title="draws over the video">▦</span>` : "",
        e.kind === "scene" ? `<span class="b-o" title="replaces the frame with a generated scene that uses the video">◈</span>` : ""].join("");
      const th = this.thumbs?.get(e.id);
      card.innerHTML = `<span class="fx-thumb${th ? " on" : ""}"${th ? ` style="background-image:url('${th}')"` : ""}></span><span class="fx-name">${e.name}</span><span class="fx-cat">${e.category}</span><span class="fx-badges">${badges}</span>`;
      card.addEventListener("dragstart", (ev) => { ev.dataTransfer.setData("text/x-effect", e.id); ev.dataTransfer.effectAllowed = "copy"; });
      card.addEventListener("dblclick", () => this.onAdd(e.id));
      card.addEventListener("mouseenter", () => { this.el.desc.textContent = e.description || e.tags.join(" · ") || e.name; this.onHover && this.onHover(e); });
      list.appendChild(card);
    }
  }
}
