<p align="center">
  <img src="Slowed/Assets.xcassets/AppIcon.appiconset/icon.png" width="128" alt="Slowed icon">
</p>

<h1 align="center">Slowed</h1>

<p align="center">
  Reproductor de música para iPhone con <b>Slowed + Reverb</b> en un toque.<br>
  An iPhone music player with one-tap <b>Slowed + Reverb</b>.
</p>

<p align="center">
  <a href="https://github.com/Harvlo/mornye-slowed-reverb/releases/latest/download/Slowed.ipa"><b>⬇️ Descargar / Download Slowed.ipa</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Harvlo/mornye-slowed-reverb/releases/latest">Releases</a>
</p>

---

## Español

### Funciones
- **Slowed + Reverb en un toque**: velocidad de 0.5x a 1.5x con tono tipo vinilo, opción de mantener el tono, tono extra ±12 semitonos, reverb ajustable con 8 tipos de sala. Presets: Slowed, Super slowed, Daycore, Nightcore y Solo reverb.
- **Ecualizador de 10 bandas** con presets (Plano, Bass Boost, Voces, Pop, Rock, Hip-Hop, Electrónica…) y bass boost aparte.
- **Efectos extra**: audio 8D, eco y «bajo el agua».
- **Biblioteca**: importa MP3, M4A, WAV, AIFF y FLAC desde Archivos (varias a la vez), o desde otra app con *Compartir › Abrir en Slowed*. Lee portada, título, artista, álbum y la marca de explícito (ID3, iTunes y FLAC).
- **Pantalla «Reproduciendo» estilo Apple Music**: portada a todo el ancho que se funde con el color dominante, barra de progreso gruesa, formato del audio (p. ej. «FLAC · 24-bit · 96 kHz»), botones grandes, AirPlay, cola, aleatorio y repetir. Audio en segundo plano y controles en la pantalla de bloqueo.
- **Letras sincronizadas**: de las etiquetas del archivo (ID3 USLT/SYLT, iTunes ©lyr, FLAC LYRICS), de un archivo .lrc o de LRCLIB.net (se puede desactivar). La línea actual se resalta y se desplaza sola; toca una línea para saltar ahí.
- **Exportar** una canción con los efectos aplicados (.m4a) y compartirla.
- **Diseño Liquid Glass** en iOS 26 y materiales translúcidos en iOS 16–25. Modo oscuro, claro o del sistema.
- **Idiomas**: español, inglés, portugués, francés, italiano, alemán y japonés (sigue el idioma del iPhone o elígelo en Ajustes).

### Instalar (sin Mac)
La IPA no está firmada; se instala con **AltStore** o **SideStore**, que la firman con tu Apple ID.

**AltStore desde Windows**
1. Instala iTunes e iCloud (versiones de la web de Apple, no de Microsoft Store) y [AltServer](https://altstore.io).
2. Conecta el iPhone por USB o a la misma Wi‑Fi e instala AltStore en el iPhone desde el icono de AltServer.
3. En el iPhone, abre el enlace de descarga de arriba en Safari y guarda `Slowed.ipa` en Archivos.
4. En AltStore › *My Apps* toca **+** y elige `Slowed.ipa`.
5. Con un Apple ID gratuito hay que refrescar la app en AltStore cada 7 días.

**SideStore**: en SideStore › *My Apps* toca **+** y elige `Slowed.ipa`.

---

## English

### Features
- **One-tap Slowed + Reverb**: 0.5x–1.5x speed with vinyl-style pitch, optional keep-pitch, extra pitch ±12 semitones, adjustable reverb with 8 room types. Presets: Slowed, Super slowed, Daycore, Nightcore and Reverb only.
- **10-band equalizer** with presets (Flat, Bass Boost, Vocals, Pop, Rock, Hip-Hop, Electronic…) plus a separate bass boost.
- **Extra effects**: 8D audio, echo and "underwater".
- **Library**: import MP3, M4A, WAV, AIFF and FLAC from Files (multi-select), or from another app via *Share › Open in Slowed*. Reads cover art, title, artist, album and the explicit flag (ID3, iTunes and FLAC tags).
- **Apple Music-style Now Playing**: edge-to-edge artwork fading into its dominant color, thick progress bar, audio format chip (e.g. "FLAC · 24-bit · 96 kHz"), big controls, AirPlay, queue, shuffle and repeat. Background audio and lock screen controls.
- **Synced lyrics**: from file tags (ID3 USLT/SYLT, iTunes ©lyr, FLAC LYRICS), a sidecar .lrc file or LRCLIB.net (can be turned off). The current line is highlighted and auto-scrolls; tap a line to jump there.
- **Export** a song with the effects baked in (.m4a) and share it.
- **Liquid Glass design** on iOS 26, translucent materials on iOS 16–25. Dark, light or system appearance.
- **Languages**: Spanish, English, Portuguese, French, Italian, German and Japanese (follows the iPhone language or pick one in Settings).

### Install (no Mac needed)
The IPA is unsigned; install it with **AltStore** or **SideStore**, which sign it with your Apple ID.

**AltStore on Windows**
1. Install iTunes and iCloud (the versions from Apple's website, not the Microsoft Store) and [AltServer](https://altstore.io).
2. Connect the iPhone by USB or on the same Wi‑Fi and install AltStore on it from the AltServer tray icon.
3. On the iPhone, open the download link above in Safari and save `Slowed.ipa` to Files.
4. In AltStore › *My Apps* tap **+** and pick `Slowed.ipa`.
5. With a free Apple ID, refresh the app in AltStore every 7 days.

**SideStore**: in SideStore › *My Apps* tap **+** and pick `Slowed.ipa`.

---

## Build
Every push to `main` builds the IPA on GitHub Actions ([`build-ipa.yml`](.github/workflows/build-ipa.yml)) with XcodeGen (`project.yml`) and publishes it as the latest release. SwiftUI + AVAudioEngine, iOS 16+.

## License
[MIT](LICENSE)
