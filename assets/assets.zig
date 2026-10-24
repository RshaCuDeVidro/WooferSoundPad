//! Files baked into the executable, so the app is a single portable binary.

pub const inter_regular = @embedFile("fonts/Inter-Regular.ttf");
pub const inter_semibold = @embedFile("fonts/Inter-SemiBold.ttf");
pub const inter_bold = @embedFile("fonts/Inter-Bold.ttf");
pub const outfit_bold = @embedFile("fonts/Outfit-Bold.ttf");
pub const mono_medium = @embedFile("fonts/JetBrainsMono-Medium.ttf");
pub const mono_bold = @embedFile("fonts/JetBrainsMono-Bold.ttf");
pub const lucide = @embedFile("fonts/lucide.ttf");

// Pages served by the local control server (OBS overlay, web deck)
pub const deck_html = @embedFile("web/deck.html");
pub const overlay_html = @embedFile("web/overlay.html");

pub const icon_256 = @embedFile("icon-256.png");
pub const icon_64 = @embedFile("icon-64.png");
pub const icon_32 = @embedFile("icon-32.png");
pub const logo_mark = @embedFile("logo-mark-128.png");
