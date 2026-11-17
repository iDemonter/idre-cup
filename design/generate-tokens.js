#!/usr/bin/env node
// Собирает app/Shared/Design/Tokens.swift из design/tokens.json.
// Запуск из корня репозитория: node design/generate-tokens.js
// tokens.json — выгрузка переменных Figma (страница «Основа»). Порядок правки: Figma → tokens.json → этот скрипт.

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const tokens = JSON.parse(fs.readFileSync(path.join(__dirname, "tokens.json"), "utf8"));
const out = path.join(root, "app", "Shared", "Design", "Tokens.swift");

function rgba(hex) {
  const h = hex.replace("#", "");
  return {
    rgb: "0x" + h.slice(0, 6).toUpperCase(),
    alpha: h.length > 6 ? Math.round((parseInt(h.slice(6, 8), 16) / 255) * 100) / 100 : 1,
  };
}

function colorExpr(light, dark) {
  const l = rgba(light);
  const d = rgba(dark);
  const alpha = l.alpha !== 1 || d.alpha !== 1 ? `, lightAlpha: ${l.alpha}, darkAlpha: ${d.alpha}` : "";
  return `Color(light: ${l.rgb}, dark: ${d.rgb}${alpha})`;
}

const lines = [];
const push = (s = "") => lines.push(s);

push("// Сгенерировано design/generate-tokens.js из design/tokens.json. Руками не править:");
push("// сначала меняется Figma (страница «Основа»), потом tokens.json, потом запускается скрипт.");
push("");
push("import SwiftUI");
push("#if canImport(UIKit)");
push("import UIKit");
push("#endif");
push("");

// Цвета
push("/// Цвета. Имена совпадают с переменными Figma (коллекция «Цвета», режимы Light и Dark).");
push("/// Один акцент — `accent`; текстом и значками на фоне — `accentText`.");
push("enum Palette {");
let group = null;
const persons = [];
for (const [name, t] of Object.entries(tokens.color)) {
  if (/^person\d+$/.test(name)) {
    persons.push([name, t]);
    continue;
  }
  if (t.group !== group) {
    if (group !== null) push("");
    push(`    // MARK: ${t.group}`);
    group = t.group;
  }
  push(`    /// ${t.note}`);
  push(`    static let ${name} = ${colorExpr(t.light, t.dark)}`);
}
push("");
push("    // MARK: Значки участников");
push("    /// 12 цветов значков участников по порядку в кубке (PersonIcon). Одинаковы в обеих темах.");
push("    static let person: [Color] = [");
for (const [name, t] of persons) {
  push(`        ${colorExpr(t.light, t.dark)}, // ${name} · ${t.note}`);
}
push("    ]");
push("");
push("    /// SF Symbol значка участника, по тому же индексу, что и `person`.");
push(`    static let personSymbols = [${tokens.personSymbols.map((s) => `"${s}"`).join(", ")}]`);
push("}");
push("");

// Отступы и радиусы
push("/// Отступы (коллекция «Размеры», группа «Отступы»).");
push("enum Spacing {");
for (const [name, t] of Object.entries(tokens.spacing)) {
  if (t.note) push(`    /// ${t.note}`);
  push(`    static let ${name}: CGFloat = ${t.value}`);
}
push("}");
push("");
push("/// Радиусы скругления (коллекция «Размеры», группа «Радиусы»). Скругления в коде — `.continuous`.");
push("enum Radius {");
for (const [name, t] of Object.entries(tokens.radius)) {
  if (t.note) push(`    /// ${t.note}`);
  push(`    static let ${name}: CGFloat = ${t.value}`);
}
push("}");
push("");

// Шрифты
const weight = { heavy: ".heavy", bold: ".bold", semibold: ".semibold", medium: ".medium", regular: ".regular" };
push("/// Шрифты: SF Pro Rounded по стилям Dynamic Type (растут с настройкой размера текста).");
push("/// Имена совпадают с текстовыми стилями Figma «Текст/…» и «Цифры/…».");
push("enum Typo {");
for (const [name, t] of Object.entries(tokens.typography)) {
  const note = `${t.figma}: ${t.size}/${t.lineHeight} ${t.weight}` + (t.note ? `. ${t.note}` : "");
  push(`    /// ${note}`);
  if (t.monospacedDigit) {
    push(`    static let ${name} = Font.system(size: ${t.size}, weight: ${weight[t.weight]}, design: .rounded).monospacedDigit()`);
  } else {
    push(`    static let ${name} = Font.system(.${t.textStyle}, design: .rounded).weight(${weight[t.weight]})`);
  }
}
push("}");
push("");
push("extension View {");
push("    /// Надстрочник «IDRE CUP 2027 · ДЕНЬ 2»: Typo.overline, прописные, трекинг.");
push("    func overlineStyle() -> some View {");
push(`        font(Typo.overline).textCase(.uppercase).tracking(${(tokens.typography.overline.size * tokens.typography.overline.tracking) / 100})`);
push("    }");
push("");
push("    /// Стеклянная подложка: Liquid Glass на iOS 26+, материал ultraThin на iOS 18.");
push("    /// На стекле — только Palette.textPrimary и Palette.accentText.");
push("    @ViewBuilder");
push("    func glassBackground<S: Shape>(in shape: S) -> some View {");
push("        #if compiler(>=6.2)");
push("        if #available(iOS 26.0, *) {");
push("            glassEffect(.regular.tint(Palette.glassTint), in: shape)");
push("        } else {");
push("            background(Palette.materialTint, in: shape).background(.ultraThinMaterial, in: shape)");
push("        }");
push("        #else");
push("        background(Palette.materialTint, in: shape).background(.ultraThinMaterial, in: shape)");
push("        #endif");
push("    }");
push("}");
push("");
push("extension Color {");
push("    /// Цвет для светлой и тёмной темы из шестнадцатеричных RGB.");
push("    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {");
push("        #if canImport(UIKit) && !os(watchOS)");
push("        self.init(uiColor: UIColor { traits in");
push("            traits.userInterfaceStyle == .dark");
push("                ? UIColor(rgb: dark, alpha: darkAlpha)");
push("                : UIColor(rgb: light, alpha: lightAlpha)");
push("        })");
push("        #else");
push("        self.init(");
push("            .sRGB,");
push("            red: Double((dark >> 16) & 0xFF) / 255,");
push("            green: Double((dark >> 8) & 0xFF) / 255,");
push("            blue: Double(dark & 0xFF) / 255,");
push("            opacity: darkAlpha");
push("        )");
push("        #endif");
push("    }");
push("}");
push("");
push("#if canImport(UIKit) && !os(watchOS)");
push("private extension UIColor {");
push("    convenience init(rgb: UInt32, alpha: Double) {");
push("        self.init(");
push("            red: CGFloat((rgb >> 16) & 0xFF) / 255,");
push("            green: CGFloat((rgb >> 8) & 0xFF) / 255,");
push("            blue: CGFloat(rgb & 0xFF) / 255,");
push("            alpha: CGFloat(alpha)");
push("        )");
push("    }");
push("}");
push("#endif");

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, lines.join("\n") + "\n");
console.log("Записано: " + path.relative(root, out));
