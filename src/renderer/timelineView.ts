// Shared timeline DOM rendering for the panel and widget.

export interface ProviderInfoLike {
  provider: string;
  displayName: string;
  color: string;
}

export interface WindowRow {
  id: string;
  accountID: string;
  provider: string;
  providerText: string;
  accountText: string;
  outerXFraction: number;
  outerWidthFraction: number;
  fillFraction: number;
  fillXFraction: number;
  nowXFraction: number;
  remainingPercentageText: string;
  relativeResetText: string;
  exactResetText: string | null;
  helpText: string;
}

export interface SectionLike {
  kind: string;
  rows: WindowRow[];
}

export interface BalanceRow {
  id: string;
  accountID: string;
  provider: string;
  providerText: string;
  accountText: string;
  labelText: string;
  valueText: string;
  cycleEndText: string | null;
}

export interface AccountStateLike {
  account: {
    id: string;
    provider: string;
    displayName: string;
  };
  snapshot: unknown | null;
  error: "requiresReauthentication" | "temporarilyUnavailable" | null;
  isRefreshing: boolean;
}

export interface TimelineLike {
  sections: SectionLike[];
  balanceRows: BalanceRow[];
}

export const SECTION_TITLES: Record<string, string> = {
  short: "5-hour windows",
  daily: "Daily windows",
  weekly: "Weekly windows",
  monthly: "Monthly windows",
  custom: "Other windows",
  "extra-credits": "Extra Credits",
};

export interface RenderHandlers {
  providerColor(provider: string): string;
  onToggleSection(section: string): void;
  onOpenAccount(accountID: string): void;
  onReconnect?(accountID: string): void;
}

function el(tag: string, className?: string, text?: string): HTMLElement {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function sectionHeader(
  title: string,
  collapsed: boolean,
  onToggle: (() => void) | null,
): HTMLElement {
  const header = el("button", `section-header${collapsed ? " collapsed" : ""}`);
  header.append(el("span", "chevron", "▾"), el("span", undefined, title));
  if (onToggle) {
    header.addEventListener("click", onToggle);
  } else {
    (header as HTMLButtonElement).disabled = true;
  }
  return header;
}

function windowRow(row: WindowRow, handlers: RenderHandlers): HTMLElement {
  const node = el("div", "row");
  node.title = row.helpText;
  node.append(
    el("span", "percent", row.remainingPercentageText),
    el("span", "provider", row.providerText),
    el("span", "account", row.accountText),
  );

  const timeline = el("div", "timeline");
  timeline.append(el("div", "track"));
  const pct = (fraction: number) => `${(fraction * 100).toFixed(2)}%`;
  const span = el("div", "window-span");
  span.style.left = pct(row.outerXFraction);
  span.style.width = pct(row.outerWidthFraction);
  timeline.append(span);
  const fill = el("div", "fill");
  fill.style.left = pct(row.fillXFraction);
  fill.style.width = pct(row.fillFraction * row.outerWidthFraction);
  fill.style.background = handlers.providerColor(row.provider);
  timeline.append(fill);
  const now = el("div", "now-line");
  now.style.left = pct(row.nowXFraction);
  timeline.append(now);
  node.append(timeline);

  const reset = el("span", "reset", row.relativeResetText);
  if (row.exactResetText) reset.title = row.exactResetText;
  node.append(reset);
  node.addEventListener("click", () => handlers.onOpenAccount(row.accountID));
  return node;
}

function ringSVG(fraction: number | null, color: string): SVGSVGElement {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 28 28");
  svg.setAttribute("width", "28");
  svg.setAttribute("height", "28");
  const track = document.createElementNS("http://www.w3.org/2000/svg", "circle");
  track.setAttribute("cx", "14");
  track.setAttribute("cy", "14");
  track.setAttribute("r", "11");
  track.setAttribute("fill", "none");
  track.setAttribute("stroke", "currentColor");
  track.setAttribute("stroke-opacity", "0.18");
  track.setAttribute("stroke-width", "3");
  svg.append(track);
  if (fraction !== null) {
    const arc = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    arc.setAttribute("cx", "14");
    arc.setAttribute("cy", "14");
    arc.setAttribute("r", "11");
    arc.setAttribute("fill", "none");
    arc.setAttribute("stroke", color);
    arc.setAttribute("stroke-width", "3");
    arc.setAttribute("stroke-linecap", "round");
    const circumference = 2 * Math.PI * 11;
    arc.setAttribute("stroke-dasharray", `${circumference}`);
    arc.setAttribute("stroke-dashoffset", `${circumference * (1 - fraction)}`);
    arc.setAttribute("transform", "rotate(-90 14 14)");
    svg.append(arc);
  }
  return svg;
}

function shelfItem(
  title: string,
  detail: string,
  fraction: number | null,
  color: string,
  onOpen: () => void,
): HTMLElement {
  const item = el("button", "shelf-item");
  item.title = `${title}: ${detail}`;
  item.append(ringSVG(fraction, color));
  item.append(el("span", "name", title));
  item.append(el("span", "detail", detail));
  item.addEventListener("click", onOpen);
  return item;
}

function balanceRow(row: BalanceRow, handlers: RenderHandlers): HTMLElement {
  const node = el("div", "balance-row");
  const dot = el("span", "dot");
  dot.style.setProperty("--dot-color", handlers.providerColor(row.provider));
  node.append(
    dot,
    el("span", "provider", row.providerText),
    el("span", "account", row.accountText),
    el("span", "label", row.labelText),
    el("span", "value", row.valueText + (row.cycleEndText ? ` · ${row.cycleEndText}` : "")),
  );
  node.title = `${row.providerText}, ${row.accountText}, ${row.labelText}, ${row.valueText}`;
  node.addEventListener("click", () => handlers.onOpenAccount(row.accountID));
  return node;
}

export function renderTimeline(
  container: HTMLElement,
  timeline: TimelineLike,
  collapsedSections: readonly string[],
  accounts: readonly AccountStateLike[],
  handlers: RenderHandlers,
): void {
  container.textContent = "";

  const attentionAccounts = accounts.filter((state) => state.error !== null);
  if (attentionAccounts.length > 0) {
    const attention = el("div", "attention");
    for (const state of attentionAccounts) {
      const row = el("div", "attention-row");
      row.append(
        el(
          "span",
          "message",
          `${state.account.displayName}: ${
            state.error === "requiresReauthentication"
              ? "sign-in required"
              : "temporarily unavailable"
          }`,
        ),
      );
      const button = el("button", undefined, "Reconnect…");
      button.addEventListener("click", () => handlers.onReconnect?.(state.account.id));
      row.append(button);
      attention.append(row);
    }
    container.append(attention);
  }

  if (timeline.sections.length === 0 && timeline.balanceRows.length === 0) {
    if (attentionAccounts.length === 0) {
      const empty = el(
        "div",
        "empty-state",
        accounts.length === 0
          ? "No accounts connected.\nOpen Settings to add one."
          : "No usage reported yet.",
      );
      empty.style.whiteSpace = "pre-line";
      container.append(empty);
    }
    return;
  }

  for (const section of timeline.sections) {
    const collapsed = collapsedSections.includes(section.kind);
    container.append(
      sectionHeader(SECTION_TITLES[section.kind] ?? section.kind, collapsed, () =>
        handlers.onToggleSection(section.kind),
      ),
    );
    if (collapsed) {
      const shelf = el("div", "shelf");
      for (const row of section.rows) {
        shelf.append(
          shelfItem(
            row.accountText || row.providerText,
            `${row.remainingPercentageText} · ${row.relativeResetText}`,
            row.fillFraction,
            handlers.providerColor(row.provider),
            () => handlers.onOpenAccount(row.accountID),
          ),
        );
      }
      container.append(shelf);
    } else {
      const rows = el("div", "section-rows");
      for (const row of section.rows) {
        rows.append(windowRow(row, handlers));
      }
      container.append(rows);
    }
  }

  if (timeline.balanceRows.length > 0) {
    if (timeline.sections.length > 0) container.append(el("div", "divider"));
    const collapsed = collapsedSections.includes("extra-credits");
    container.append(
      sectionHeader("Extra Credits", collapsed, () =>
        handlers.onToggleSection("extra-credits"),
      ),
    );
    if (collapsed) {
      const shelf = el("div", "shelf");
      for (const row of timeline.balanceRows) {
        shelf.append(
          shelfItem(
            row.accountText || row.providerText,
            row.valueText,
            null,
            handlers.providerColor(row.provider),
            () => handlers.onOpenAccount(row.accountID),
          ),
        );
      }
      container.append(shelf);
    } else {
      const rows = el("div", "section-rows");
      for (const row of timeline.balanceRows) {
        rows.append(balanceRow(row, handlers));
      }
      container.append(rows);
    }
  }
}
