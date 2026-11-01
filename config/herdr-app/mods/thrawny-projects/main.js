import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { spaces, machines, focused, exec, home, pickFolder, run, theme, props, closeOverlay, nextCommand } from "herdr";

export default class Projects extends View {
  init(_props, cx) {
    this.machine = spaces().find(s => s.id === focused()?.space)?.machine ?? null;
    this.projects = [];
    this.filter = "";
    this.at = 0;
    this.error = "";
    this.loading = true;
    this.handle = cx.focus_handle();
    this.input = InputState.new({ placeholder: "Find a project, or type an absolute path…" });
    this.input.on("change", (_e, cx) => { this.filter = this.input.value(); this.at = 0; cx.notify(); });
    this.input.on("submit", (_e, cx) => this.open(false, cx));
    this.input.focus();
    this.load(cx);
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        if (command === "focus") this.open(true, cx);
      }
    });
  }

  load(cx) {
    const machine = this.machine;
    this.loading = true;
    this.error = "";
    this.projects = [];
    cx.spawn(async (cx) => {
      try {
        const result = await exec("project-picker", ["--list"], { on: machine });
        if (result.code) throw new Error(result.stderr || "Project discovery failed");
        if (this.machine !== machine) return;
        this.projects = [...new Set(result.stdout.trim().split("\n").filter(Boolean))];
      } catch (e) { if (this.machine === machine) this.error = String(e); }
      if (this.machine === machine) this.loading = false;
      cx.notify();
    });
  }

  rows() {
    const terms = this.filter.toLowerCase().trim().split(/\s+/);
    return this.projects.filter(p => terms.every(t => p.toLowerCase().includes(t)));
  }

  close() { closeOverlay(props().overlay); }

  open(focusOnly, cx, selected) {
    if (this.opening) return;
    const typed = this.filter.trim();
    let folder = selected ?? (typed.startsWith("/") || typed.startsWith("~/") ? typed : this.rows()[this.at]);
    if (!folder) return;
    const machine = this.machine;
    this.opening = true;
    cx.spawn(async (cx) => {
      try {
        if (folder.startsWith("~/")) {
          // Resolve the target home, not this app's home for SSH machines.
          const r = machine ? await exec("printenv", ["HOME"], { on: machine }) : { code: 0, stdout: home() };
          if (r.code) throw new Error("Could not find the target home directory");
          folder = r.stdout.trim() + folder.slice(1);
        }
        const result = await exec("realpath", ["--", folder], { on: machine });
        if (result.code) throw new Error("Path does not exist");
        folder = result.stdout.trim();
        const directory = await exec("test", ["-d", folder], { on: machine });
        if (directory.code) throw new Error("Choose a directory");
        const existing = spaces().find(s => s.machine === machine && s.folder === folder);
        if (existing) {
          run("space.select", { id: existing.id });
          if (!focusOnly) run("tab.new", { space: existing.id, folder });
        } else run("space.new", { name: folder.split("/").pop(), folder, ...(machine ? { machine } : {}) });
        this.close();
      } catch (e) { this.error = String(e); this.opening = false; cx.notify(); }
    });
  }

  render(cx) {
    const t = theme();
    const rows = this.rows();
    this.at = Math.min(this.at, Math.max(0, rows.length - 1));
    const start = Math.max(0, this.at - 5);
    const visible = rows.slice(start, start + 10);
    const rowHeight = 56;
    const choices = machines().filter(m => m.layout === "ready");
    return v_flex().id("projects").track_focus(this.handle).w_full().min_h(0).p(18).gap(10).bg(t.popover)
      .on_key_down((e, cx) => {
        if (e.key === "escape") { this.close(); cx.stop_propagation(); }
        else if (e.key === "up" || e.key === "down") {
          this.at = (this.at + (e.key === "up" ? -1 : 1) + rows.length) % (rows.length || 1);
          cx.stop_propagation(); cx.notify();
        }
      })
      .child(h_flex().items_center().gap(8)
        .child(div().flex_1().font_semibold().text_size(15).text_color(t.foreground).child("Projects"))
        .children(choices.map(m => div().id(`machine-${m.name ?? "local"}`).px(8).py(4).rounded(5)
          .bg(this.machine === m.name ? t.selected : t.surface).text_color(this.machine === m.name ? t.foreground : t.muted)
          .text_size(11).cursor_pointer().on_click((_e, cx) => { this.machine = m.name; this.at = 0; this.load(cx); this.input.focus(); cx.notify(); })
          .child(m.name ?? "This machine"))))
      .child(div().h(36).px(10).border_1().border_color(t.accent).rounded(6)
        .child(Input.new(this.input).h_full().w_full().text_color(t.foreground).text_size(13)))
      .when(this.loading, el => el.child(div().text_color(t.muted).text_size(12).child("Finding projects…")))
      .when(Boolean(this.error), el => el.child(div().text_color(t.blocked).text_size(12).child(this.error)))
      // Scrolling content does not supply an intrinsic height to this popup.
      .child(v_flex().h(Math.min(340, visible.length * rowHeight)).min_h(0).overflow_y_scrollbar().children(visible.map((folder, offset) => {
        const i = start + offset;
        const open = spaces().some(s => s.machine === this.machine && s.folder === folder);
        return h_flex().id(`project-${i}`).h(rowHeight).flex_none().px(8).py(8).gap(12).rounded(5).cursor_pointer()
          .bg(i === this.at ? t.selected : t.popover).hover(s => s.bg(t.hover))
          .on_click((_e, cx) => this.open(false, cx, folder))
          .child(v_flex().flex_1().min_w(0).gap(2)
            .child(div().text_size(13).text_color(t.foreground).child(folder.split("/").pop()))
            .child(div().text_size(11).text_color(t.muted).truncate().child(folder)))
          .when(open, el => el.child(div().text_size(11).text_color(t.muted).child("Open")));
      })))
      .when(!this.loading && !rows.length, el => el.child(div().text_color(t.muted).text_size(12).child("No matching projects. Enter a folder path to open it.")))
      .child(h_flex().items_center().gap(12)
        .child(div().flex_1().text_size(11).text_color(t.muted).child("Enter: new tab   Shift+Enter: focus existing   Esc: cancel"))
        .when(this.machine === null, el => el.child(div().id("browse").text_size(12).text_color(t.accent).cursor_pointer().child("Choose folder…")
          .on_click((_e, cx) => cx.spawn(async (cx) => { const folder = await pickFolder(); if (folder) this.open(false, cx, folder); })))));
  }
}
