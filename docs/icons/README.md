# Pomolog's icons

- `Pomodorolog.icon`, at the package root: the droplet's own icon, a tomato
  with a summit flag, on cream, and on dark grey in dark mode.
- `StickerBook.icon`: the tile on the Sticker book link in Settings, a star
  sticker on an album, white on pink.
- `History.icon`: the tile on the History link, a clock whose rim turns back,
  white on blue.

All three are Icon Composer documents, so they open in Icon Composer, and all
three are drawn by `generator/icons.py`. Change a drawing there and run it
again, rather than editing the generated files by hand:

```bash
python3 docs/icons/generator/icons.py
```

It rewrites the three documents and
`Sources/Pomodorolog/Surfaces/SettingsTiles.swift`, which carries the two tiles
as 56 by 56 pixel renders, the size DroppyKit asks for. The renders come from
Icon Composer's own `ictool`, which ships with Xcode 26 and later, so the tiles
get the same glass, edge light and shadow as Droppy's own. Add
`--preview <folder>` to also write PNG renders of each icon to look at.

The droplet's icon is a single layer on purpose. Icon Composer draws its first
group in front, while DroppyKit's flat preview of a document, which the harness
shows, draws groups in the order they are stored. With one layer, both draw
the same picture.
