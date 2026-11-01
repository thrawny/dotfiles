import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, focused, hc, theme, props, closeOverlay, nextCommand, notify } from "herdr";

const ACTIONS = {
  c: ["tab.new", "New tab"],
  h: ["tab.prev", "Previous tab"], p: ["tab.prev", "Previous tab"],
  l: ["tab.next", "Next tab"], n: ["tab.next", "Next tab"],
  j: ["agent.next", "Next agent"], k: ["agent.prev", "Previous agent"],
  v: ["pane.split:right", "Split right"], "-": ["pane.split:down", "Split down"],
  x: ["pane.close", "Close pane"], "shift-x": ["tab.close", "Close tab"],
  z: ["pane.zoom", "Zoom pane"], tab: ["thrawny-agents.cycle-pane", "Next pane"],
  "shift-,": ["thrawny-agents.tab-left", "Move tab left"],
  "shift-.": ["thrawny-agents.tab-right", "Move tab right"],
  "shift-r": ["thrawny-agents.reset-order", "Reset agent order"],
};
for (let i = 1; i <= 9; i++) ACTIONS[String(i)] = [`thrawny-agents.agent-${i}`, `Agent ${i}`];

export default class Prefix extends View {
  init(_props, cx) {
    this.terminal = focused()?.shown ?? focused()?.terminal;
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        if (command === "literal") this.literal(cx);
      }
    });
  }

  close() { closeOverlay(props().overlay); }

  literal(cx) {
    const terminal = this.terminal;
    if (!terminal) return;
    cx.spawn(async (cx) => {
      try {
        const result = await hc(["keys", terminal, "ctrl+a"]);
        if (result.code) throw new Error(result.stderr);
        this.close();
      } catch (e) { notify({ title: "Could not send Ctrl+A", body: String(e), level: "error" }); }
    });
  }

  activate(action) {
    this.close();
    if (action.startsWith("pane.split:")) run("pane.split", { direction: action.split(":")[1] });
    else run(action);
  }

  render() {
    const t = theme();
    return v_flex().id("prefix").track_focus(this.handle).w_full().p(16).gap(5).bg(t.popover)
      .on_key_down((e, cx) => {
        cx.stop_propagation();
        if (e.key === "escape") return this.close();
        if (e.key === "a" && !e.modifiers.platform && !e.modifiers.alt) return this.literal(cx);
        const key = e.modifiers.shift ? `shift-${e.key.toLowerCase()}` : e.key;
        // GPUI can report shifted punctuation as its typed character.
        const entry = ACTIONS[key] ?? ACTIONS[e.key === "<" ? "shift-," : e.key === ">" ? "shift-." : e.key];
        if (entry) this.activate(entry[0]);
        else this.close();
      })
      .child(h_flex().items_center().pb(8)
        .child(div().flex_1().font_semibold().text_color(t.foreground).child("Ctrl+A"))
        .child(div().text_size(11).text_color(t.muted).child("Esc to cancel")))
      .children([
        ["c", "New tab"], ["v / −", "Split right / down"], ["x / Shift+X", "Close pane / tab"],
        ["h / l", "Previous / next tab"], ["j / k", "Next / previous agent"],
        ["1–9", "Focus agent"], ["Tab / z", "Cycle / zoom pane"],
        ["< / >", "Move tab left / right"], ["Shift+R", "Reset agent order"], ["a / Ctrl+A", "Send literal Ctrl+A"],
      ].map(([key, label]) => h_flex().gap(12).py(4)
        .child(div().w(135).text_size(12).text_color(t.accent).child(key))
        .child(div().text_size(12).text_color(t.foreground).child(label))));
  }
}
