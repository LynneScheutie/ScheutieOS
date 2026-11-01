// L10n.swift — interface language for the app chrome (menus, dialogs, About).
//
// Scope: **only the app's own fixed elements** — the menu bar, dialogs and the
// About window. The page, the conversation, the user's input and the AI's output
// are never touched by any of this; the language setting cannot reach them.
//
// Chinese source strings double as the lookup keys, and every translation is
// baked into `rows` below. A missing entry degrades to the Chinese text instead
// of to an empty label, and `--self-test-lang` scans every language for exactly
// that mistake.
//
// Why baked tables instead of the system Translation framework:
// `TranslationSession(installedSource:target:)` exists on macOS 26+ and looks
// like the obvious way to auto-translate these strings, but it only works once
// the user has downloaded each language pair by hand in System Settings —
// `prepareTranslation()` throws `TranslationError.notInstalled` and
// `canRequestDownloads` is false, both from a plain CLI and from a real
// NSApplication with `.regular` activation. Measured on macOS 27: all seven
// pairs report `.supported` but not installed, and every translate call fails.
// So the translations live here instead. Instant, offline, deterministic.

import Foundation

enum AppLanguage: Int, CaseIterable {
    case chinese = 0
    case english
    case french
    case russian
    case spanish
    case arabic
    case japanese
    case korean

    /// Shown in the language menu. Each language names *itself*, so these are
    /// never translated — you must be able to find your own language in a list
    /// you cannot read.
    var title: String {
        switch self {
        case .chinese:  return "中文"
        case .english:  return "English"
        case .french:   return "Français"
        case .russian:  return "Русский"
        case .spanish:  return "Español"
        case .arabic:   return "العربية"
        case .japanese: return "日本語"
        case .korean:   return "한국어"
        }
    }

    /// BCP-47-ish tag, for logs and future use.
    var code: String {
        switch self {
        case .chinese:  return "zh-Hans"
        case .english:  return "en"
        case .french:   return "fr"
        case .russian:  return "ru"
        case .spanish:  return "es"
        case .arabic:   return "ar"
        case .japanese: return "ja"
        case .korean:   return "ko"
        }
    }

    /// The app itself never mirrors its layout, so this is informational: Arabic
    /// strings render right-to-left *inside* the menu item, but the menus stay
    /// left-to-right. Flip the whole app and the custom About window would need a
    /// rework, which is out of scope for a string translation.
    var isRightToLeft: Bool { self == .arabic }

    /// Column index into `L.rows`, in the same order as `allCases`.
    var column: Int { rawValue }
}

enum L {

    private(set) static var lang: AppLanguage = .chinese

    static func set(_ language: AppLanguage) { lang = language }

    /// Pass-through in Chinese, table lookup otherwise. A missing entry yields the
    /// Chinese string, which is visible rather than silent — and caught by
    /// `--self-test-lang`.
    static func t(_ zh: String) -> String {
        guard lang != .chinese else { return zh }
        return tables[lang]?[zh] ?? zh
    }

    static func hasTranslation(_ zh: String, in language: AppLanguage) -> Bool {
        language == .chinese || tables[language]?[zh] != nil
    }

    // MARK: - Script probes (used by the self test)

    private static func any(_ s: String, in ranges: [ClosedRange<UInt32>]) -> Bool {
        s.unicodeScalars.contains { sc in ranges.contains { $0.contains(sc.value) } }
    }

    static func hasCJK(_ s: String) -> Bool {
        any(s, in: [0x3400...0x4DBF, 0x4E00...0x9FFF])
    }
    static func hasKana(_ s: String) -> Bool { any(s, in: [0x3040...0x30FF]) }
    static func hasHangul(_ s: String) -> Bool { any(s, in: [0x1100...0x11FF, 0xAC00...0xD7AF]) }
    static func hasCyrillic(_ s: String) -> Bool { any(s, in: [0x0400...0x04FF]) }
    static func hasArabicScript(_ s: String) -> Bool { any(s, in: [0x0600...0x06FF, 0x0750...0x077F]) }

    // MARK: - Strings with interpolation
    //
    // These can't be plain dictionary values either, so each one formats a
    // template that lives in the same table. Keeps every translatable string in
    // one place, including the ones with placeholders.

    private static func f(_ zh: String, _ args: CVarArg...) -> String {
        String(format: t(zh), arguments: args)
    }

    static func aboutPill(version: String, build: String) -> String {
        f("版本 %@ (build %@)", version, build)
    }

    static func aboutFooter(site: String) -> String {
        f("基于 WKWebView 构建 · %@", site)
    }

    static func appearanceChanged(_ name: String) -> String {
        f("外观已切换为：%@", name)
    }

    static func languageChanged(_ language: AppLanguage) -> String {
        f("语言已切换为 %@", language.title)
    }

    static func copiedMarkdown(_ n: Int) -> String {
        f("已复制 %d 字符的 Markdown 到剪贴板", n)
    }

    static func copiedSelection(_ n: Int) -> String {
        f("已复制选中的 %d 字符", n)
    }

    static func copiedAllText(_ n: Int) -> String {
        f("已复制全文（%d 字符）", n)
    }

    static func exportedTo(_ name: String) -> String {
        f("已导出到 %@", name)
    }

    static func textStats(chars: Int, cjk: Int, words: Int) -> String {
        f("共 %d 字符 · 中文 %d 字 · 英文 %d 词", chars, cjk, words)
    }

    static func customUAHint() -> String {
        t("留空则回退到默认 Safari 标识。修改后会重新载入页面。")
    }

    // MARK: - The table
    //
    // One row per source string: the Chinese key, then the translation for each
    // language in `AppLanguage` order. Columns are laid out 1:1 with the enum, so
    // adding a language means adding one column here and one case above.

    /// Column order: zh, en, fr, ru, es, ar, ja, ko
    private typealias Row = (String, String, String, String, String, String, String, String)

    private static let rows: [Row] = [
        // ---- Application menu
        ("关于 ScheutieOS", "About ScheutieOS", "À propos de ScheutieOS", "О программе ScheutieOS", "Acerca de ScheutieOS", "حول ScheutieOS", "ScheutieOS について", "ScheutieOS 정보"),
        ("隐藏 ScheutieOS", "Hide ScheutieOS", "Masquer ScheutieOS", "Скрыть ScheutieOS", "Ocultar ScheutieOS", "إخفاء ScheutieOS", "ScheutieOS を隠す", "ScheutieOS 가리기"),
        ("隐藏其他", "Hide Others", "Masquer les autres", "Скрыть остальные", "Ocultar otras", "إخفاء الأخرى", "ほかを隠す", "기타 가리기"),
        ("显示全部", "Show All", "Tout afficher", "Показать все", "Mostrar todo", "إظهار الكل", "すべてを表示", "모두 보기"),
        ("退出 ScheutieOS", "Quit ScheutieOS", "Quitter ScheutieOS", "Завершить ScheutieOS", "Salir de ScheutieOS", "إنهاء ScheutieOS", "ScheutieOS を終了", "ScheutieOS 종료"),

        // ---- Edit
        ("编辑", "Edit", "Édition", "Правка", "Edición", "تحرير", "編集", "편집"),
        ("撤销", "Undo", "Annuler", "Отменить", "Deshacer", "تراجع", "取り消す", "실행 취소"),
        ("重做", "Redo", "Rétablir", "Повторить", "Rehacer", "إعادة", "やり直す", "다시 실행"),
        ("剪切", "Cut", "Couper", "Вырезать", "Cortar", "قص", "カット", "오려두기"),
        ("拷贝", "Copy", "Copier", "Скопировать", "Copiar", "نسخ", "コピー", "복사"),
        ("粘贴", "Paste", "Coller", "Вставить", "Pegar", "لصق", "ペースト", "붙여넣기"),
        ("全选", "Select All", "Tout sélectionner", "Выбрать все", "Seleccionar todo", "تحديد الكل", "すべてを選択", "모두 선택"),
        ("查找…", "Find…", "Rechercher…", "Найти…", "Buscar…", "بحث…", "検索…", "찾기…"),

        // ---- Conversation (its own top-level menu)
        ("对话", "Conversation", "Conversation", "Диалог", "Conversación", "المحادثة", "会話", "대화"),
        ("导出对话为 Markdown…", "Export Conversation as Markdown…", "Exporter la conversation en Markdown…", "Экспортировать диалог в Markdown…", "Exportar conversación como Markdown…", "تصدير المحادثة بصيغة Markdown…", "会話を Markdown として書き出す…", "대화를 Markdown으로 내보내기…"),
        ("导出对话为 Markdown", "Export Conversation as Markdown", "Exporter la conversation en Markdown", "Экспортировать диалог в Markdown", "Exportar conversación como Markdown", "تصدير المحادثة بصيغة Markdown", "会話を Markdown として書き出す", "대화를 Markdown으로 내보내기"),
        ("复制对话为 Markdown", "Copy Conversation as Markdown", "Copier la conversation en Markdown", "Скопировать диалог в Markdown", "Copiar conversación como Markdown", "نسخ المحادثة بصيغة Markdown", "会話を Markdown としてコピー", "대화를 Markdown으로 복사"),
        ("复制选中内容为 Markdown", "Copy Selection as Markdown", "Copier la sélection en Markdown", "Скопировать выделенное в Markdown", "Copiar selección como Markdown", "نسخ التحديد بصيغة Markdown", "選択範囲を Markdown としてコピー", "선택 항목을 Markdown으로 복사"),
        ("复制全文（纯文本）", "Copy All Text (Plain)", "Copier tout le texte (brut)", "Скопировать весь текст (простой)", "Copiar todo el texto (sin formato)", "نسخ كل النص (نص عادي)", "全文をコピー（プレーンテキスト）", "전체 텍스트 복사(일반 텍스트)"),
        ("导出为纯文本文件…（.txt）", "Export as Plain Text File… (.txt)", "Exporter en fichier texte… (.txt)", "Экспортировать в текстовый файл… (.txt)", "Exportar como archivo de texto… (.txt)", "تصدير كملف نص عادي… (.txt)", "プレーンテキストファイルとして書き出す…（.txt）", "일반 텍스트 파일로 내보내기… (.txt)"),
        ("导出为纯文本", "Export as Plain Text", "Exporter en texte brut", "Экспортировать как простой текст", "Exportar como texto sin formato", "تصدير كنص عادي", "プレーンテキストとして書き出す", "일반 텍스트로 내보내기"),
        ("统计对话字数", "Conversation Text Stats", "Statistiques du texte", "Статистика текста", "Estadísticas del texto", "إحصاءات نص المحادثة", "会話の文字数", "대화 글자 수"),
        ("打印 / 存储为 PDF…", "Print / Save as PDF…", "Imprimer / Enregistrer au format PDF…", "Печать / Сохранить как PDF…", "Imprimir / Guardar como PDF…", "طباعة / حفظ بصيغة PDF…", "プリント／PDF として保存…", "프린트 / PDF로 저장…"),

        // ---- View
        ("显示", "View", "Présentation", "Вид", "Visualización", "عرض", "表示", "보기"),
        ("重新载入", "Reload", "Recharger", "Обновить", "Recargar", "إعادة تحميل", "再読み込み", "재로드"),
        ("回到首页", "Go Home", "Aller à l’accueil", "На главную", "Ir al inicio", "الانتقال إلى الرئيسية", "ホームに戻る", "홈으로 이동"),
        ("放大", "Zoom In", "Agrandir", "Увеличить", "Ampliar", "تكبير", "拡大", "확대"),
        ("缩小", "Zoom Out", "Réduire", "Уменьшить", "Reducir", "تصغير", "縮小", "축소"),
        ("实际大小", "Actual Size", "Taille réelle", "Реальный размер", "Tamaño real", "الحجم الفعلي", "実際のサイズ", "실제 크기"),
        ("进入全屏幕", "Enter Full Screen", "Passer en plein écran", "Полноэкранный режим", "Entrar en pantalla completa", "ملء الشاشة", "フルスクリーンにする", "전체 화면 시작"),

        // ---- Enhance
        ("增强", "Enhance", "Améliorations", "Улучшения", "Mejoras", "تحسينات", "拡張", "향상 기능"),
        ("外观", "Appearance", "Apparence", "Оформление", "Apariencia", "المظهر", "外観", "모양"),
        ("语言", "Language", "Langue", "Язык", "Idioma", "اللغة", "言語", "언어"),
        ("浏览器标识 (User-Agent)", "User-Agent", "User-Agent", "User-Agent", "User-Agent", "معرّف المتصفح (User-Agent)", "ユーザーエージェント", "브라우저 식별자 (User-Agent)"),
        ("页面样式", "Page Style", "Style de la page", "Стиль страницы", "Estilo de la página", "نمط الصفحة", "ページスタイル", "페이지 스타일"),
        ("重置所有增强设置", "Reset All Enhancements", "Réinitialiser les améliorations", "Сбросить все улучшения", "Restablecer todas las mejoras", "إعادة تعيين كل التحسينات", "すべての拡張設定をリセット", "모든 향상 설정 재설정"),
        ("跟随系统", "Follow System", "Suivre le système", "Как в системе", "Seguir el sistema", "حسب النظام", "システムに合わせる", "시스템 설정 따르기"),
        ("强制暗色", "Force Dark", "Forcer le mode sombre", "Тёмная тема", "Forzar oscuro", "فرض الوضع الداكن", "ダーク表示にする", "어둡게 강제"),
        ("强制亮色", "Force Light", "Forcer le mode clair", "Светлая тема", "Forzar claro", "فرض الوضع الفاتح", "ライト表示にする", "밝게 강제"),

        // ---- User-Agent presets (names in Enhance.swift double as these keys)
        ("Safari (macOS) — 默认", "Safari (macOS) — Default", "Safari (macOS) — par défaut", "Safari (macOS) — по умолчанию", "Safari (macOS) — predeterminado", "Safari (macOS) — افتراضي", "Safari (macOS) — デフォルト", "Safari (macOS) — 기본"),
        ("自定义…", "Custom…", "Personnalisé…", "Другой…", "Personalizado…", "مخصّص…", "カスタム…", "사용자화…"),
        ("自定义…（当前已启用）", "Custom… (active)", "Personnalisé… (actif)", "Другой… (активен)", "Personalizado… (activo)", "مخصّص… (مُفعَّل)", "カスタム…（使用中）", "사용자화…(사용 중)"),
        ("重置为默认", "Reset to Default", "Réinitialiser par défaut", "Сбросить по умолчанию", "Restablecer predeterminado", "إعادة التعيين إلى الافتراضي", "デフォルトに戻す", "기본값으로 재설정"),

        // ---- Page style
        ("隐藏滚动条", "Hide Scrollbars", "Masquer les barres de défilement", "Скрыть полосы прокрутки", "Ocultar barras de desplazamiento", "إخفاء أشرطة التمرير", "スクロールバーを隠す", "스크롤 막대 가리기"),
        ("禁用动画与过渡", "Disable Animations & Transitions", "Désactiver animations et transitions", "Отключить анимацию и переходы", "Desactivar animaciones y transiciones", "تعطيل الحركات والانتقالات", "アニメーションとトランジションを無効にする", "동작 및 전환 효과 끄기"),
        ("自定义 CSS…", "Custom CSS…", "CSS personnalisé…", "Свой CSS…", "CSS personalizado…", "CSS مخصّص…", "カスタム CSS…", "사용자 CSS…"),
        ("自定义 CSS…（已设置）", "Custom CSS… (set)", "CSS personnalisé… (défini)", "Свой CSS… (задан)", "CSS personalizado… (definido)", "CSS مخصّص… (مضبوط)", "カスタム CSS…（設定済み）", "사용자 CSS…(설정됨)"),
        ("清除自定义 CSS", "Clear Custom CSS", "Effacer le CSS personnalisé", "Очистить свой CSS", "Borrar CSS personalizado", "مسح CSS المخصّص", "カスタム CSS を消去", "사용자 CSS 지우기"),
        ("重新应用样式", "Reapply Styles", "Réappliquer les styles", "Применить стили заново", "Reaplicar estilos", "إعادة تطبيق الأنماط", "スタイルを再適用", "스타일 다시 적용"),
        ("自定义 CSS 已清除", "Custom CSS cleared", "CSS personnalisé effacé", "Свой CSS очищен", "CSS personalizado borrado", "تم مسح CSS المخصّص", "カスタム CSS を消去しました", "사용자 CSS를 지웠습니다"),
        ("样式已重新应用", "Styles reapplied", "Styles réappliqués", "Стили применены заново", "Estilos reaplicados", "تم إعادة تطبيق الأنماط", "スタイルを再適用しました", "스타일을 다시 적용했습니다"),
        ("已重置所有增强设置", "All enhancements reset", "Améliorations réinitialisées", "Все улучшения сброшены", "Mejoras restablecidas", "تمت إعادة تعيين كل التحسينات", "すべての拡張設定をリセットしました", "모든 향상 설정을 재설정했습니다"),

        // ---- History / Window
        ("历史记录", "History", "Historique", "История", "Historial", "السجل", "履歴", "방문 기록"),
        ("后退", "Back", "Précédent", "Назад", "Atrás", "رجوع", "戻る", "뒤로"),
        ("前进", "Forward", "Suivant", "Вперёд", "Adelante", "تقدّم", "進む", "앞으로"),
        ("窗口", "Window", "Fenêtre", "Окно", "Ventana", "نافذة", "ウインドウ", "윈도우"),
        ("新建窗口", "New Window", "Nouvelle fenêtre", "Новое окно", "Nueva ventana", "نافذة جديدة", "新規ウインドウ", "새로운 윈도우"),
        ("最小化", "Minimize", "Réduire", "Убрать в Dock", "Minimizar", "تصغير", "しまう", "최소화"),
        ("关闭窗口", "Close Window", "Fermer la fenêtre", "Закрыть окно", "Cerrar ventana", "إغلاق النافذة", "ウインドウを閉じる", "윈도우 닫기"),
        ("缩放", "Zoom", "Zoom", "Масштаб", "Zoom", "تكبير", "ズーム", "확대/축소"),
        ("显示主窗口", "Show Main Window", "Afficher la fenêtre principale", "Показать главное окно", "Mostrar ventana principal", "إظهار النافذة الرئيسية", "メインウインドウを表示", "메인 윈도우 보기"),

        // ---- Dialogs
        ("保存", "Save", "Enregistrer", "Сохранить", "Guardar", "حفظ", "保存", "저장"),
        ("取消", "Cancel", "Annuler", "Отмена", "Cancelar", "إلغاء", "キャンセル", "취소"),
        ("确定", "OK", "OK", "ОК", "Aceptar", "موافق", "OK", "확인"),
        ("好", "OK", "OK", "ОК", "Aceptar", "موافق", "OK", "확인"),
        ("提示", "Notice", "Remarque", "Уведомление", "Aviso", "تنبيه", "お知らせ", "알림"),
        ("确认", "Confirm", "Confirmation", "Подтверждение", "Confirmar", "تأكيد", "確認", "확인"),
        ("输入", "Input", "Saisie", "Ввод", "Entrada", "إدخال", "入力", "입력"),
        ("导出失败", "Export Failed", "Échec de l’export", "Ошибка экспорта", "Error al exportar", "فشل التصدير", "書き出しに失敗", "내보내기 실패"),
        ("统计失败", "Could not read the page", "Lecture impossible", "Не удалось прочитать страницу", "No se pudo leer la página", "تعذّرت قراءة الصفحة", "ページを読み取れません", "페이지를 읽을 수 없습니다"),
        ("自定义 User-Agent", "Custom User-Agent", "User-Agent personnalisé", "Свой User-Agent", "User-Agent personalizado", "User-Agent مخصّص", "カスタム User-Agent", "사용자 User-Agent"),
        ("自定义 CSS", "Custom CSS", "CSS personnalisé", "Свой CSS", "CSS personalizado", "CSS مخصّص", "カスタム CSS", "사용자 CSS"),
        ("直接写下要注入的 CSS 规则，会应用到站点的所有页面。", "Write the CSS rules to inject. They apply to every page of the site.", "Écrivez les règles CSS à injecter. Elles s’appliquent à toutes les pages du site.", "Напишите правила CSS для внедрения. Они применяются ко всем страницам сайта.", "Escribe las reglas CSS que se van a inyectar. Se aplican a todas las páginas del sitio.", "اكتب قواعد CSS التي تريد حقنها. ستُطبَّق على كل صفحات الموقع.", "挿入する CSS ルールを記述してください。サイトのすべてのページに適用されます。", "삽입할 CSS 규칙을 작성하세요. 사이트의 모든 페이지에 적용됩니다."),
        ("没能从当前页面提取到对话内容。\n可能页面还没加载完，或站点结构有变化。", "Could not extract the conversation from this page.\nIt may still be loading, or the site layout changed.", "Impossible d’extraire la conversation de cette page.\nElle est peut-être encore en cours de chargement, ou la mise en page du site a changé.", "Не удалось извлечь диалог с этой страницы.\nВозможно, она ещё загружается или вёрстка сайта изменилась.", "No se pudo extraer la conversación de esta página.\nPuede que siga cargando o que la maquetación del sitio haya cambiado.", "تعذّر استخراج المحادثة من هذه الصفحة.\nقد تكون الصفحة ما زالت تُحمَّل أو تغيّر تخطيط الموقع.", "このページから会話を抽出できませんでした。\nまだ読み込み中か、サイトの構成が変わった可能性があります。", "이 페이지에서 대화를 추출할 수 없습니다.\n아직 로딩 중이거나 사이트 구조가 바뀌었을 수 있습니다."),
        ("没能从当前页面提取到内容。\n可能页面还没加载完，或站点结构有变化。", "Could not extract anything from this page.\nIt may still be loading, or the site layout changed.", "Impossible d’extraire du contenu de cette page.\nElle est peut-être encore en cours de chargement, ou la mise en page du site a changé.", "Не удалось извлечь содержимое с этой страницы.\nВозможно, она ещё загружается или вёрстка сайта изменилась.", "No se pudo extraer nada de esta página.\nPuede que siga cargando o que la maquetación del sitio haya cambiado.", "تعذّر استخراج أي محتوى من هذه الصفحة.\nقد تكون الصفحة ما زالت تُحمَّل أو تغيّر تخطيط الموقع.", "このページから内容を抽出できませんでした。\nまだ読み込み中か、サイトの構成が変わった可能性があります。", "이 페이지에서 내용을 추출할 수 없습니다.\n아직 로딩 중이거나 사이트 구조가 바뀌었을 수 있습니다."),
        ("没选中内容", "Nothing Selected", "Aucune sélection", "Ничего не выбрано", "Nada seleccionado", "لا يوجد تحديد", "選択範囲がありません", "선택된 항목 없음"),
        ("请先用鼠标选中想导出的部分，再执行这个命令。", "Select the part you want to export first, then run this command again.", "Sélectionnez d’abord la partie à exporter, puis relancez cette commande.", "Сначала выделите нужный фрагмент, затем повторите команду.", "Selecciona primero la parte que quieres exportar y vuelve a ejecutar el comando.", "حدِّد الجزء الذي تريد تصديره أولًا ثم نفّذ الأمر مرة أخرى.", "先に書き出したい部分を選択してから、もう一度このコマンドを実行してください。", "먼저 내보낼 부분을 선택한 다음 이 명령을 다시 실행하세요."),

        // ---- About window
        ("开 发 者", "D E V E L O P E R", "D É V E L O P P E U R", "Р А З Р А Б О Т Ч И К", "D E S A R R O L L A D O R", "المطور", "開 発 者", "개 발 자"),

        // ---- Templates with placeholders (see the `f(_:_:)` helpers above)
        ("版本 %@ (build %@)", "Version %@ (build %@)", "Version %@ (build %@)", "Версия %@ (сборка %@)", "Versión %@ (compilación %@)", "الإصدار %@ (البنية %@)", "バージョン %@（ビルド %@）", "버전 %@ (빌드 %@)"),
        ("基于 WKWebView 构建 · %@", "Built with WKWebView · %@", "Construit avec WKWebView · %@", "На основе WKWebView · %@", "Creado con WKWebView · %@", "مبني على WKWebView · %@", "WKWebView で構築 · %@", "WKWebView 기반 · %@"),
        ("外观已切换为：%@", "Appearance: %@", "Apparence : %@", "Оформление: %@", "Apariencia: %@", "المظهر: %@", "外観：%@", "모양: %@"),
        ("语言已切换为 %@", "Language: %@", "Langue : %@", "Язык: %@", "Idioma: %@", "اللغة: %@", "言語：%@", "언어: %@"),
        ("已复制 %d 字符的 Markdown 到剪贴板", "Copied %d characters of Markdown", "%d caractères de Markdown copiés", "Скопировано %d символов Markdown", "Se copiaron %d caracteres de Markdown", "تم نسخ %d حرفًا من Markdown", "Markdown を %d 文字コピーしました", "Markdown %d자를 복사했습니다"),
        ("已复制选中的 %d 字符", "Copied %d characters of the selection", "%d caractères de la sélection copiés", "Скопировано %d символов выделенного", "Se copiaron %d caracteres de la selección", "تم نسخ %d حرفًا من التحديد", "選択した %d 文字をコピーしました", "선택한 %d자를 복사했습니다"),
        ("已复制全文（%d 字符）", "Copied all text (%d characters)", "Tout le texte copié (%d caractères)", "Скопирован весь текст (%d символов)", "Se copió todo el texto (%d caracteres)", "تم نسخ كل النص (%d حرفًا)", "全文をコピーしました（%d 文字）", "전체 텍스트를 복사했습니다(%d자)"),
        ("已导出到 %@", "Exported to %@", "Exporté vers %@", "Экспортировано в %@", "Exportado a %@", "تم التصدير إلى %@", "%@ に書き出しました", "%@에 내보냈습니다"),
        ("共 %d 字符 · 中文 %d 字 · 英文 %d 词", "%d characters · %d CJK · %d words", "%d caractères · %d CJK · %d mots", "%d символов · %d иероглифов · %d слов", "%d caracteres · %d CJK · %d palabras", "%d حرفًا · %d صيني · %d كلمة", "%d 文字 · 中文 %d 字 · 英単語 %d", "%d자 · 중국어 %d자 · 영어 %d단어"),
        ("留空则回退到默认 Safari 标识。修改后会重新载入页面。", "Leave empty to fall back to the default Safari identity. The page reloads after a change.", "Laissez vide pour revenir à l’identité Safari par défaut. La page est rechargée après modification.", "Оставьте пустым, чтобы вернуться к стандартному Safari. После изменения страница перезагрузится.", "Déjalo vacío para volver a la identidad Safari predeterminada. La página se recarga tras el cambio.", "اتركه فارغًا للرجوع إلى هوية Safari الافتراضية. تُعاد تحميل الصفحة بعد التغيير.", "空欄にすると既定の Safari として扱われます。変更後はページが再読み込みされます。", "비워 두면 기본 Safari로 돌아갑니다. 변경 후 페이지가 다시 로드됩니다."),
    ]

    /// Built once, from `rows`. `chinese` maps to nothing — it is the key itself.
    private static let tables: [AppLanguage: [String: String]] = {
        var out: [AppLanguage: [String: String]] = [:]
        for language in AppLanguage.allCases where language != .chinese {
            let col = language.column
            var table: [String: String] = [:]
            table.reserveCapacity(rows.count)
            for row in rows {
                let values = [row.0, row.1, row.2, row.3, row.4, row.5, row.6, row.7]
                guard col < values.count else { continue }
                table[row.0] = values[col]
            }
            out[language] = table
        }
        return out
    }()

    // MARK: - Self test support

    /// Strings that are deliberately identical in every language: product names.
    ///
    /// The self test subtracts these instead of demanding a translation. The list
    /// is explicit on purpose — a new string that should stay in English must be
    /// added here, so it can never be silently forgotten, and nothing else can
    /// hide behind a broad rule.
    ///
    /// Note `Safari (macOS) — 默认` is *not* here: it carries a translatable word,
    /// so it gets a real translation in all seven languages.
    static func isVerbatim(_ s: String) -> Bool {
        s == kAppName
            || s == "Chrome (macOS)" || s == "Chrome (Windows)"
            || s == "Safari (iPhone)" || s == "Safari (iPad)"
    }

    /// Every source key, in table order. Used by `--self-test-lang`.
    static var allKeys: [String] { rows.map { $0.0 } }

    /// How many distinct keys the table holds. If this is smaller than
    /// `rows.count` a duplicate Chinese key silently swallowed a row.
    static var keyCount: Int { Set(rows.map { $0.0 }).count }
}
