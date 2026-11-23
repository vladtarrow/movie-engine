<div align="center">

# Movie Engine

**AI agent montira vaš video u Kdenliveu dok vi gledate, a posao možete preuzeti u svakom trenutku.**

AI agenti za programiranje (Claude Code, Codex) prave i mijenjaju prave Kdenlive projekte: filmove, objašnjavajuće snimke i vertikalne kratke videe. Izmjene se odmah pojavljuju u editoru koji imate otvoren. Prenosivo, Windows, bez zakrpa za editor.

![Platform: Windows 10/11](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![Kdenlive 26.08.3](https://img.shields.io/badge/Kdenlive-26.08.3-527EB2)
![Agents: Claude Code | Codex](https://img.shields.io/badge/agents-Claude%20Code%20%7C%20Codex-8A5CF6)
![Portable](https://img.shields.io/badge/install-portable-2EA44F)

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Français](README.fr.md) · [العربية](README.ar.md) · [বাংলা](README.bn.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [اردو](README.ur.md) · [Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [日本語](README.ja.md) · [Türkçe](README.tr.md) · [한국어](README.ko.md) · [Українська](README.uk.md) · [Italiano](README.it.md) · [Polski](README.pl.md) · [Tiếng Việt](README.vi.md) · [فارسی](README.fa.md) · [ไทย](README.th.md) · [Kiswahili](README.sw.md) · [አማርኛ](README.am.md) · [Avañe'ẽ](README.gn.md) · [Setswana](README.tn.md) · [Shqip](README.sq.md) · [Беларуская](README.be.md) · [Български](README.bg.md) · [Bosanski](README.bs.md) · [Hrvatski](README.hr.md) · [Српски](README.sr.md) · **Crnogorski** · [Македонски](README.mk.md) · [Slovenščina](README.sl.md) · [Slovenčina](README.sk.md) · [Čeština](README.cs.md) · [Magyar](README.hu.md) · [Română](README.ro.md) · [Dansk](README.da.md) · [Norsk bokmål](README.nb.md) · [Norsk nynorsk](README.nn.md) · [Svenska](README.sv.md) · [Íslenska](README.is.md) · [Suomi](README.fi.md) · [Eesti](README.et.md) · [Latviešu](README.lv.md) · [Lietuvių](README.lt.md) · [Nederlands](README.nl.md) · [Lëtzebuergesch](README.lb.md) · [Rumantsch](README.rm.md) · [Ελληνικά](README.el.md) · [Malti](README.mt.md) · [Gaeilge](README.ga.md) · [Català](README.ca.md) · [ქართული](README.ka.md) · [Հայերեն](README.hy.md) · [Azərbaycanca](README.az.md) · [Afrikaans](README.af.md) · [isiZulu](README.zu.md) · [isiXhosa](README.xh.md) · [Sesotho](README.st.md) · [Sepedi](README.nso.md) · [Xitsonga](README.ts.md) · [Tshivenḓa](README.ve.md) · [siSwati](README.ss.md) · [isiNdebele (South Africa)](README.nr.md) · [isiNdebele (Zimbabwe)](README.nd.md) · [chiShona](README.sn.md) · [Chichewa](README.ny.md) · [Ikinyarwanda](README.rw.md) · [Ikirundi](README.rn.md) · [Malagasy](README.mg.md) · [Soomaali](README.so.md) · [Afaan Oromoo](README.om.md) · [Qafar af](README.aa.md) · [ትግርኛ](README.ti.md) · [Sängö](README.sg.md) · [Kreol Seselwa](README.crs.md) · [TjiKalanga](README.kck.md) · [ChiNdau](README.ndc.md)

*Ovo je prevod. Referentna verzija je README na engleskom jeziku.*

</div>

---

## Sadržaj

- [Zašto](#zašto)
- [Kako radi](#kako-radi)
- [Mogućnosti](#mogućnosti)
- [Zahtjevi](#zahtjevi)
- [Instalacija](#instalacija)
- [Brzi početak](#brzi-početak)
- [Rad sa agentom](#rad-sa-agentom)
- [Komandna linija za montažu (`kdp.ps1`)](#komandna-linija-za-montažu-kdpps1)
- [Sinhronizacija sa otvorenim editorom](#sinhronizacija-sa-otvorenim-editorom)
- [Generatori: ono što Kdenlive ne umije](#generatori-ono-što-kdenlive-ne-umije)
- [Glas i zvuk](#glas-i-zvuk)
- [Jezik interfejsa](#jezik-interfejsa)
- [Struktura foldera](#struktura-foldera)
- [Testovi i dokazi](#testovi-i-dokazi)
- [Ograničenja](#ograničenja)
- [Rješavanje problema](#rješavanje-problema)
- [Česta pitanja](#česta-pitanja)
- [Doprinos](#doprinos)
- [Zahvalnice](#zahvalnice)
- [Licenca](#licenca)

## Zašto

Video editori su napravljeni za ruku na mišu. AI agenti su dobri u strukturi, tajmingu i ponavljanju: da rasporede 300 klipova u ritmu muzike, da svaki titl vežu za glas, da prerade scenu nakon primjedbi. Ali ne mogu da klikću kroz grafički interfejs, a da ne preuzmu vašu radnu površinu.

Kdenlive je snažan editor otvorenog koda, ali na Windowsu **nema API za automatizaciju**: upravljanje preko D-Busa postoji samo u verzijama za Linux, a forkovi koji ga dodaju ili se više ne održavaju ili nijesu bezbjedni. Movie Engine to rješava bez zakrpa za editor:

1. Agent mijenja fajl projekta `.kdenlive` preko testirane komandne linije (`engine/kdp.ps1`).
2. Pokrenutom Kdenliveu se preko Windows UI Automation zadaje da ponovo učita fajl, bez pritisaka tastera, bez miša i bez otimanja fokusa.
3. Vaše nesačuvane izmjene se prvo sačuvaju i nikad se ne prepisuju.

Dakle, agent montira, a vi pregledate, ili sami uređujete rukom. Oboje radite na istom projektu, u istom editoru, u isto vrijeme.

## Kako radi

```mermaid
flowchart LR
    U[You] -- prompt --> A[AI agent<br/>Claude Code / Codex]
    A -- "kdp.ps1 &lt;command&gt;" --> P[(project.kdenlive)]
    A -- generators --> M[materials/aigenerated<br/>clips, voice, overlays]
    M -- bin-add --> P
    P -- "kd-watch: reload<br/>(UI Automation, File &gt; Revert)" --> K[Kdenlive<br/>running on your desktop]
    K -- "kd-pull: save your edits first" --> P
    U -- review, hand edits, Render --> K
```

Svaka komanda za montažu prolazi isti bezbjedni ciklus:

1. **Pull.** Ako Kdenlive ima nesačuvane izmjene, zadaje mu se da ih sačuva (dugme Save na traci s alatkama, preko UI Automation), i čuvanje se potvrđuje.
2. **Izmjena.** Komanda mijenja XML pod zaključavanjem, nakon provjere heša i sa snimkom stanja za poništavanje. Ako se fajl u međuvremenu promijenio, ništa se ne upisuje.
3. **Ponovno učitavanje.** Posmatrač vidi oznaku AI-ja i u otvorenom editoru pokreće File > Revert. Uspjehom se smatra samo slučaj kad je vidžet vremenske linije zaista ponovo izgrađen.
4. **Konflikt.** Ako ste u međuvremenu počeli da uređujete, ništa se ne učitava ponovo i vaš rad ostaje. AI verzija se čuva sa strane, a agent ponovo primjenjuje svoju izmjenu preko vaše.

## Mogućnosti

- **Potpuna montaža projekta bez grafičkog interfejsa**: oko 120 komandi koje pokrivaju korpu projekta, vremensku liniju, efekte, kompozicije, trake, vodilice, markere, titlove, sekvence, brzinu i preraspodjelu vremena, slajdšou, natpise, proksije, renderovanje i poništavanje/ponavljanje. Pogledajte [pregled komandi](#komandna-linija-za-montažu-kdpps1).
- **Sinhronizacija sa otvorenim editorom.** AI izmjene se pojavljuju u Kdenliveu u koji gledate; vaše nesačuvane izmjene se prvo sačuvaju i nikad se ne gube.
- **Nikad ne ometa vašu radnu površinu.** Nema otimanja fokusa, pritisaka tastera ni pokreta miša. Testni editori rade na nevidljivoj Windows radnoj površini.
- **Prenosivo.** Editor, podešavanja, Node.js, fontovi i alatke nalaze se u jednom folderu. Kopirajte ga na drugi računar i radi; ništa se ne upisuje u Program Files ni u vaš Windows profil.
- **Generatori za ono što Kdenlive ne umije**: kinetički tekst s animacijom slovo po slovo, rukom crtane oznake, 3D scene interfejsa, animacije kursora i dugi interaktivni objašnjavajući filmovi. Renderuju se na GPU-u sa pravim zamućenjem pokreta i postavljaju na vremensku liniju kao obični klipovi.
- **Glas sa tajmingom riječi** (Microsoft Edge TTS, bez API ključa). Titlovi i radnje okidaju se tačno na pravoj riječi.
- **Sintetizovani zvučni efekti** (whoosh, click, pop, riser, impact i drugi), generisani kodom.
- **Dokazano, ne pretpostavljeno.** Svaka komanda ima provjeru rezultata, efekti i kompozicije se provjeravaju jedan po jedan, a sirovi rezultati se nalaze u `docs/proof/`.
- **Uputstva za agente uključena.** `AGENTS.md` i vještine u `.claude/skills/` uče Claude Code i Codex toku rada, formatu fajla i zamkama.

## Zahtjevi

| | |
|---|---|
| OS | Windows 10 ili 11, x64 |
| Editor | Kdenlive **26.08.3**, prenosiva (standalone) verzija. Ostale verzije nijesu testirane. |
| Node.js | 18 ili noviji: `.zip` za Windows x64 sa nodejs.org, raspakovan u `engine/node/` |
| Pregledač | Microsoft Edge (dio Windowsa); renderi scena ga koriste u headless režimu |
| Agent | [Claude Code](https://claude.com/claude-code) ili Codex. Nije obavezno: svaka alatka radi i ručno. |
| Disk | oko 1 GB za editor i alatke, plus vaši mediji |
| GPU | bilo koji GPU sa hardverskim H.264 kodiranjem ubrzava `film-render.mjs` (bez njega se koristi softversko kodiranje) |

## Instalacija

Sve se instalira **unutar foldera**. Ništa ne traži administratorska prava.

```powershell
git clone https://github.com/vladtarrow/movie-engine.git
cd movie-engine
```

**1. Node.js.** Preuzmite `.zip` za Windows x64 sa Node.js 18 ili novijim sa <https://nodejs.org/en/download> i raspakujte njegov sadržaj u `engine\node\`, tako da se tamo nađu `engine\node\node.exe` i `engine\node\npm.cmd`. Nijesu potrebni ni instaler ni sistemski Node. Sve skripte se pokreću preko `engine\node.cmd`, nikad preko sistemskog Nodea.

**2. Node paketi** za alatku za glas i za rendere (verzije su fiksirane u `engine/voice/package.json`):

```powershell
engine\node\npm.cmd install --prefix engine\voice
```

**3. Prenosivi Kdenlive 26.08.3.** Preuzmite `kdenlive-26.08.3_standalone.exe` sa <https://download.kde.org/stable/kdenlive/26.08/windows/> u `engine\installer\`, provjerite ga i raspakujte:

```powershell
(Get-FileHash engine\installer\kdenlive-26.08.3_standalone.exe -Algorithm SHA256).Hash
# expected: A25427B1DFF2C17E3B0386E991BB1A719382BB3176D1A90E441CDAEB6E0A967D
engine\installer\kdenlive-26.08.3_standalone.exe -o"engine\Kdenlive" -y
```

Editor završi u `engine\Kdenlive\kdenlive-26.08.3_standalone\bin\`. Već sadrži `melt.exe` i `ffmpeg.exe`.

**4. Prvo pokretanje.**

```powershell
engine\kdenlive.cmd
```

Kdenlive čuva sva svoja podešavanja u `engine\profile-kdenlive\`, a ne u vašem Windows profilu. Pri prvom pokretanju jednom prikazuje čarobnjak za podešavanje.

## Brzi početak

### Sa agentom

Otvorite folder u Claude Code (ili Codex) i zamolite običnim riječima:

> Napravi novi vertikalni projekat „launch-teaser“ od 30 fps. Postavi na vremensku liniju tri snimka ekrana iz `materials/designers/launch/`, svaki po 2,5 s sa kratkim pretapanjem, dodaj glas iz `script.txt` i veži kinetički natpis za svaki red.

> Otvori mi ga u Kdenliveu.

> Drugi kadar je predug. Skrati ga na 1,8 s i podigni logo malo više.

Agent prati `AGENTS.md`: uređuje preko `kdp.ps1`, renderuje samo klipove koji su montaži potrebni i drži otvoreni editor usklađenim. Vi pregledate u Kdenliveu, uređujete rukom kad god hoćete i pritisnete Render kad ste zadovoljni.

### Ručno

```powershell
# a new 1080x1920 30 fps project with 2 video and 2 audio tracks
powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 new -Project projects\hello\hello.kdenlive -Profile vertical_hd_30

# a 3-second title and a colour background
powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 bin-color -Project projects\hello\hello.kdenlive -Color '#203060' -Seconds 3 -Name bg
powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 title -Project projects\hello\hello.kdenlive -Text "Hello" -Seconds 3 -Name hi

# place them: background on V1, title above it on V2
powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 add -Project projects\hello\hello.kdenlive -Bin bg -Track V1 -At 0
powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 add -Project projects\hello\hello.kdenlive -Bin hi -Track V2 -At 0

# a check frame, then open it in the editor
powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 frame -Project projects\hello\hello.kdenlive -At 1.5 -Out out\hello\check.png
engine\kdenlive.cmd projects\hello\hello.kdenlive
```

Da kasnije ponovo otvorite posljednji projekat, dvaput kliknite na `open-last-project.cmd`.

## Rad sa agentom

Agent čita `AGENTS.md` (Codex) ili `CLAUDE.md`, koji ga uvozi (Claude Code), kao i dvije vještine:

| Vještina | Čemu uči |
|---|---|
| `.claude/skills/kdenlive-project-file` | format `.kdenlive` / MLT XML, `kdp.ps1`, provjera pomoću `melt` |
| `.claude/skills/kdenlive-live` | bezbjedno upravljanje pokrenutim editorom: pokretanje, pull, ponovno učitavanje, snimak njegovog prozora |

Pravila koja agent poštuje i na koja se možete osloniti:

- Nikad ne uzima vaš miš, tastaturu ni fokus i nikad ne snima vašu radnu površinu (samo prozor samog editora).
- Korake u grafičkom interfejsu (sačuvaj, otvori, ponovo učitaj) radi sam, umjesto da vas moli da kliknete.
- Pita prije nego što bilo šta preuzme i prije nego što bilo šta obriše.
- Renderuje samo ono što je poslu potrebno (klipove scena, kontrolne kadrove). Konačni film renderuje samo kad to zatražite.
- Kad Kdenlive nešto ne umije dobro da uradi, agent to napravi spolja kodom i ubaci rezultat kao klip. Efekat ne razvodnjava.

## Komandna linija za montažu (`kdp.ps1`)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 <command> -Project <file.kdenlive> [options]
```

Vrijeme se zadaje u sekundama, sa tačkom (`2.5`). Trake su `V1 V2 …` (V1 je najniža) i `A1 A2 …`. Klip se određuje sa `-Track` plus bilo koji trenutak `-At` unutar njega. Parametri efekata idu u `-Params "name=value||name=value"`. Potpun spisak sa svim opcijama nalazi se u zaglavlju `engine/kdp.ps1`.

| Grupa | Komande |
|---|---|
| Projekat | `new`, `profiles`, `info`, `validate`, `fonts`, `profile-set`, `profile-from-clip`, `zone`, `archive`, `backups`, `rebase`, `otio-export`, `otio-import` |
| Korpa projekta | `bin-add`, `bin-color`, `title`, `title-text`, `title-save`, `title-template`, `bin-rename`, `bin-remove`, `bin-info`, `bin-set`, `bin-duplicate`, `bin-replace-file`, `bin-reload`, `folder`, `bin-folder`, `relink`, `clean`, `generator`, `playlist-clip`, `extract-audio`, `transcode` |
| Vremenska linija | `add`, `add-av`, `move`, `copy`, `trim`, `ripple-trim`, `slip`, `split`, `remove`, `speed`, `remap`, `disable`, `enable`, `group`, `ungroup`, `mix`, `unmix`, `space-insert`, `space-remove`, `spaces-remove-all`, `track-clear`, `replace-in-timeline` |
| Efekti | `effects`, `effect-info`, `effect-add`, `effect-list`, `effect-set`, `effect-remove`, `effect-copy`, `effect-clear`, `effects-all`, `bin-effect`, `effect-templates`, `effect-template` |
| Kompozicije | `compositions`, `comp-info`, `comp-add`, `comp-list`, `comp-set`, `comp-remove` |
| Trake | `track-add`, `track-remove`, `track-set` |
| Vodilice i markeri | `guide-add`, `guide-list`, `guide-remove`, `guide-set`, `guide-clear`, `guide-export`, `guide-category`, `marker`, `marker-list`, `marker-set`, `marker-remove` |
| Titlovi | `sub-add`, `sub-import`, `sub-export`, `sub-state` |
| Sekvence | `sequence-add`, `sequences`, `copy-to-sequence`, `expand`; svaka komanda sa `-Sequence <name>` radi unutar te sekvence |
| Posebno | `slideshow`, Lottie / Glaxnimate animacije preko `bin-add`, `proxy`, `stabilize`, `scene-split`, `speed-job`, `subclip` |
| Izlaz | `frame` (jedan PNG), `preview` (brzi render preko melt), `render` (Kdenliveov sopstveni renderer ili preset), `presets` |
| Istorija | `undo`, `redo`, `clear-history` (snimci stanja u `projects/<name>/.kdp-history`) |

Ponašanje koje vrijedi znati:

- Povezane audio i video polovine se zajedno pomjeraju, skraćuju, sijeku i uklanjaju (`-Alone` za samo jednu polovinu).
- Komanda koja ne uspije izlazi sa kodom 1 i ništa ne upisuje.
- Efekti koje Windows verzija ne može da izvrši se odbijaju, a ne prećutno zanemaruju (spisak: `docs/proof/assets.txt`).
- Svaka radnja iz Kdenliveovog menija je u `engine/tools/data/kdenlive-actions.csv` povezana sa komandom, drugim putem ili oznakom „samo prikaz“. Pogledajte `docs/kdenlive-coverage.md`.

## Sinhronizacija sa otvorenim editorom

| Skripta | Šta radi | Izlazni kodovi |
|---|---|---|
| `engine\kd-pull.ps1 -Project <f>` | tjera Kdenlive da sačuva vaše izmjene i to potvrđuje | 0 fajl je ažuran, 3 nije pokrenut, 4 nije potvrđeno |
| `engine\kd-reload.ps1 -Project <f>` | File > Revert, potvrđeno ponovo izgrađenom vremenskom linijom | 0 potvrđeno, 2 imate nesačuvane izmjene (ništa nije odbačeno), 3 nije pokrenut, 4 neuspjeh |
| `engine\kd-watch.ps1 -Project <f>` | posmatrač u pozadini: ponovo učitava nakon svakog AI upisa, bilježi konflikte | dnevnik u `engine\kd-watch.log`; za zaustavljanje obrišite `engine\kd-watch.run` |
| `engine\kdenlive-bg.ps1 [project]` | pokreće Kdenlive minimizovan za agenta | 0 učitano, 4 nije potvrđeno |
| `engine\kdenlive.cmd [project]` | pokreće Kdenlive za vas | |

Pokrenite posmatrača jednom po sesiji:

```powershell
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','engine\kd-watch.ps1','-Project','projects\hello\hello.kdenlive'
```

Veliki projekti: ponovno učitavanje projekta sa 1000 klipova traje minutima, a alatke ga čekaju umjesto da prerano prijave rezultat. Projekti se otvaraju preko *File > Open Recent* u praznom editoru, jer pri direktnom otvaranju fajla Qt prolazi kroz svaki element vremenske linije zbog pristupačnosti, što je bilo oko 10 minuta sporije.

## Generatori: ono što Kdenlive ne umije

Kdenlive/MLT nema animaciju teksta slovo po slovo, nema izraze (expressions) i ima malo 3D-a, a teški efekti usporavaju reprodukciju. Movie Engine takve djelove renderuje spolja i postavlja ih na vremensku liniju kao obične klipove, obično sa alfa kanalom, na traku iznad slike. Skripta generatora i njeni ulazni podaci ostaju u folderu projekta, pa se klip može ponovo generisati kad se promijeni tekst, font ili tajming.

| Alatka | Pravi |
|---|---|
| `engine/tools/kinetic-text.ps1` | kinetičke natpise s animacijom slovo po slovo, svaka riječ vremenski usklađena iz `voice.json`, okvir za isticanje |
| `engine/tools/annotate.ps1` | rukom crtane krugove, okvire, podvlačenja i strelice koji se iscrtavaju preko snimka ekrana |
| `engine/tools/card-entrance.ps1` | karticu sa snimkom ekrana koja se podiže i uvećava uz meku śenku |
| `engine/tools/pdf-to-png.ps1` | slajdove iz PDF izvoza |
| `engine/tools/html-render.mjs` | bilo koju HTML/CSS/canvas scenu u video: animaciju interfejsa, kursore, 3D, maske |
| `engine/tools/film-render.mjs` + `film/` | duge, interaktivne objašnjavajuće filmove na canvasu: jedan klip po rečenici glasa, radnje okidaju na izgovorenim riječima, zamućenje pokreta na GPU-u pri oko 45 fps |

Oba renderera upravljaju Microsoft Edgeom koji dolazi sa Windowsom, u headless režimu, sa jednokratnim profilom i bez pristupa mreži.

### Demo

```powershell
# a 3-second 3D title card with a cursor click
engine\node.cmd engine\tools\html-render.mjs examples\demo\scene\scene.html examples\demo\out --frames 0,30,60,89
engine\node.cmd engine\tools\html-render.mjs examples\demo\scene\scene.html examples\demo\out\scene.mp4

# a 4-shot interactive film timed to two voice lines
engine\node.cmd engine\tools\film-render.mjs examples\demo\film\film.html examples\demo\out --check
engine\node.cmd engine\tools\film-render.mjs examples\demo\film\film.html examples\demo\out --shots all --width 640
engine\node.cmd engine\tools\film-render.mjs examples\demo\film\film.html examples\demo\out\clips --suffix -v01
```

Film čine tri mala fajla. `data.js` sadrži kadrove i vremena riječi. `direction.js` ima po jedan red za svaki kadar:

```text
1 | hover 192 108 @brand | tag 300 60 Your brand @deserves | confetti 192 90 @film
2 say=A film that/*explains* it
3 | click 116 108 @before | click 268 108 @after | chips Before~After @after
4 scene=counter | count 0 120 % @count
```

`scenes.js` sadrži kadrove koji se crtaju od nule. `@word` okida radnju kad glas izgovori tu riječ. Među radnjama su click, hover, drag, zoom, lens, ring, arrow, chips, toggle, slider, toast, type, count i confetti; potpuna sintaksa je na početku `engine/tools/film/film-kit.js`.

## Glas i zvuk

```powershell
engine\node.cmd engine\voice\voice.mjs lines.json materials\aigenerated\hello\voice en-US-AndrewMultilingualNeural +0%
```

`lines.json` je spisak rečenica. Alatka upisuje po jedan mp3 za svaku rečenicu i `voice.json`, sa trajanjem te početkom i krajem svake riječi. Rečenice se keširaju, pa se pri promjeni jedne rečenice ponovo generiše samo ona. Koristi se onlajn sinteza govora Microsoft Edgea preko paketa `msedge-tts`: ključ nije potreban, ali servis je nezvaničan i traži internet.

```powershell
engine\node.cmd engine\audio\sfx.mjs materials\aigenerated\sfx
```

Ovo kodom sintetizuje whoosh, whoosh-long, swipe, click, pop, tick, riser, impact, ding i reveal; gotov komplet se nalazi u `materials/aigenerated/sfx/`. Zvuke kraće od jednog kadra prije postavljanja dopunite tišinom (`-af apad=whole_dur=0.0667`).

## Jezik interfejsa

Pokretači podrazumijevano otvaraju Kdenlive na **engleskom**. Za drugi jezik, prije pokretanja postavite `MOVIE_ENGINE_UI_LANG`:

```powershell
$env:MOVIE_ENGINE_UI_LANG = 'ru'; engine\kdenlive.cmd
```

UI Automation pronalazi stavke menija po njihovim vidljivim nazivima. Nazivi za 31 jezik interfejsa su već ugrađeni (`engine/tools/kd-ui.ps1`, `$KdNames`). Za bilo koji drugi jezik dodajte tamo njegove nazive i provjerite pomoću:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-langcheck.ps1
```

## Struktura foldera

```text
movie-engine/
├─ AGENTS.md, CLAUDE.md          instructions for AI agents
├─ .claude/skills/               agent skills: project file format, live editor
├─ engine/
│  ├─ kdp.ps1                    the editing command line
│  ├─ kd-pull / kd-reload / kd-watch .ps1, kdenlive.cmd, kdenlive-bg.ps1
│  ├─ tools/                     internals, generators, tests, data (action map)
│  ├─ voice/  audio/  fonts/     TTS, synthesized SFX, Poppins (OFL)
│  ├─ Kdenlive/  node/           portable editor and Node.js (not in git)
│  └─ profile-kdenlive/          the editor's settings (not in git)
├─ projects/<name>/<name>.kdenlive
├─ materials/
│  ├─ download/                  stock and downloaded files (not in git)
│  ├─ aigenerated/               everything the AI made (sfx/ and test-kit/ ship with the engine)
│  ├─ designers/  brand/         files from your team, brand assets
├─ examples/demo/                demos of the scene and film renderers
├─ out/                          renders (not in git)
└─ docs/                         proofs, coverage, translations of this README
```

Putanje do medija unutar projekata su relativne. Ako premjestite ili kopirate folder, `kdp.ps1 rebase` (koji automatski pokreće i `kdenlive.cmd`) upisuje novu lokaciju u projekat.

## Testovi i dokazi

Tvrdnje o tome šta radi potkrijepljene su provjerama rezultata, a ne time što se „funkcija izvršila“. Sažetak je u [`docs/kdenlive-proof.md`](../../docs/kdenlive-proof.md), a sirovi izlaz u `docs/proof/`.

| Test | Šta provjerava |
|---|---|
| `engine\tools\kdp-clitest.ps1` | svaku komandu `kdp.ps1`, preko komandne linije, upoređujući dobijeni projekat |
| `engine\tools\kd-livetest.ps1` | pull, ponovno učitavanje, posmatrača, konflikte i trke sa pravim Kdenliveom na nevidljivoj radnoj površini |
| `engine\tools\kdp-assetsweep.ps1` | svaki efekat i kompoziciju: renderuje i upoređuje kadrove |
| `engine\tools\kdp-portabletest.ps1` | kopira folder na drugo mjesto i radi iz kopije |
| `engine\tools\kd-langcheck.ps1` | jezik interfejsa i to da UI Automation pronalazi meni |
| `engine\tools\kdp-coverage-check.ps1` | da je svaka radnja menija povezana i da nijedan dokaz nije stariji od koda |

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-clitest.ps1 -Report docs\proof\clitest.txt
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-livetest.ps1 -Report docs\proof\live-en.txt
```

Testni editori rade samo na skrivenoj radnoj površini sa sopstvenim profilom, pa testovi nikad ne diraju vaš otvoreni Kdenlive ni vaš fokus.

## Ograničenja

- **Samo Windows**, samo Kdenlive **26.08.3**. Linux ima D-Bus i trebao bi mu drugačiji most.
- Pokretanje editora uzima fokus tastature na oko 3 sekunde dok se pojavljuje prazan prozor. Agenti pitaju prije nego što ga pokrenu dok vi radite. Ponovna učitavanja i izmjene ne uzimaju fokus.
- Windows verziji nedostaju MLT moduli sox, ladspa i movit i neki frei0r/avfilter efekti; `kdp.ps1` ih odbija (`docs/proof/assets.txt`).
- Izvoz i uvoz OpenTimelineIO prenose samo klipove i praznine. Multicam nema prebacivanje uglova uživo (rezovi se prave pomoću split/remove/hide).
- „Save As…“ preko UI Automation na minimizovanom prozoru ne otvara dijalog; agent umjesto toga koristi `archive` ili kopije fajlova.
- Prepoznavanje govora (automatski titlovi) traži Whisper ili Vosk, koji nijesu uključeni.
- Natpisi napravljeni Kdenliveovom alatkom za natpise koriste fontove instalirane u Windowsu. Za zagarantovanu tipografiju renderujte tekst generatorima, koji učitavaju fontove iz `engine/fonts/`.
- Edge TTS je nezvanični onlajn servis i može da se promijeni ili prestane da radi.

## Rješavanje problema

| Simptom | Uzrok i rješenje |
|---|---|
| Kdenlive je pokrenut, ali klik na njega na traci zadataka ništa ne prikazuje | Njegov sačuvani položaj prozora je van ekrana. Zatvorite ga i obrišite unose `kdockLayout` u `engine\profile-kdenlive\AppData\Local\kdenliverc`, ili pomjerite prozor pomoću `SetWindowPos` (pogledajte `AGENTS.md`). |
| `kd-reload.ps1` izlazi sa kodom 2 | Imate nesačuvane izmjene. Ništa nije odbačeno. Pokrenite `kd-pull.ps1`, pa ponovo primijenite izmjenu (`kdp.ps1` to radi sam). |
| `CONFLICT` u `engine\kd-watch.log` | Vi i agent ste uređivali u istom trenutku. Vaša verzija ostaje u editoru, a AI verzija je u `projects\<name>\.kdp-history\<name>\conflict\`. Zamolite agenta da ponovo primijeni svoju izmjenu. |
| Komanda izlazi sa kodom 1 i porukom „pull not confirmed“ | Kdenlive je zauzet ili prikazuje dijalog. Zatvorite dijalog ili sačekajte da se učitavanje završi, pa ponovite. |
| PowerShell skripta se ne može raščlaniti | Skripte sa tekstom koji nije ASCII moraju biti sačuvane kao UTF-8 **sa BOM** za Windows PowerShell 5.1. |
| `voice.mjs` staje sa „Stream closed before the synthesis completed“ | Obično problem s mrežom, ili neizbjegnuti SSML u starijim kopijama. `voice.mjs` sam izbjegava `& < >`. |
| Otvaranje velikog projekta traje mnogo minuta | Otvarajte ga preko `kdenlive.cmd` / `kdenlive-bg.ps1`, nikad kao `kdenlive.exe project.kdenlive`. |

## Česta pitanja

**Da li mi treba Claude Code ili Codex?**
Ne. Svaka alatka je obična skripta koju možete pokrenuti ručno. Agent je ono što posao čini brzim: planira montažu, pokreće alatke i drži editor usklađenim.

**Hoće li agent prepisati moje ručne izmjene?**
Neće. Prije svakog upisa vaše nesačuvane izmjene se sačuvaju i potvrde. Ako uređujete dok agent upisuje, upis se odbija ili čuva sa strane kao konflikt, a nikad se ne primjenjuje preko vašeg rada.

**Mogu li i dalje normalno koristiti Kdenlive?**
Da. To je standardni Kdenlive sa sopstvenim folderom podešavanja. Uređujte, pregledajte i renderujte kao i obično.

**Da li radi sa Kdenliveom koji već imam instaliran?**
Koristi sopstvenu prenosivu kopiju u `engine\Kdenlive\`, pa vaš instalirani Kdenlive i njegova podešavanja ostaju netaknuti.

**Zašto ne fork Kdenlivea sa API-jem, ili neki drugi editor?**
Na Windowsu ne postoji održavan i bezbjedan fork (pregled iz novembra 2026). Procijenjeni su OpenShot, Blender VSE, DaVinci Resolve, Shotcut i veb editori; Kdenlive je dao najveću dubinu montaže. Prijedlog REST API-ja u glavnom projektu (merge request !902) se prati.

**Može li da renderuje konačni video?**
Može, pomoću `kdp.ps1 render` (Kdenliveov sopstveni renderer, skriveno), ili sami pritisnete Render u editoru.

**Da li se moji mediji negđe otpremaju?**
Ne. Samo se tekst za glas šalje servisu Edge TTS kad generišete glas. Renderi scena rade sa isključenom mrežom.

## Doprinos

Doprinosi su dobrodošli. Pogledajte [CONTRIBUTING.md](../../CONTRIBUTING.md). Ukratko:

- Svaka nova ili izmijenjena operacija `kdp.ps1` traži provjeru rezultata u `kdp-clitest.ps1`, unos u mapi radnji i novo pokretanje `kdp-coverage-check.ps1`.
- Nikad ne pokrećite testni Kdenlive na vidljivoj radnoj površini; koristite `engine/tools/kd-hidden.ps1`.
- Održavajte sve prenosivim: bez instalacija van foldera, bez apsolutnih putanja u projektima.
- Provjerene posebnosti zapišite u `AGENTS.md` ili u odgovarajuću vještinu.

## Zahvalnice

- [Kdenlive](https://kdenlive.org) i [MLT](https://www.mltframework.org): editor i pogon ispod njega.
- [FFmpeg](https://ffmpeg.org), isporučen uz Kdenlive.
- [msedge-tts](https://www.npmjs.com/package/msedge-tts) za glas.
- [Poppins](https://fonts.google.com/specimen/Poppins) od Indian Type Foundry, SIL Open Font License (`engine/fonts/OFL.txt`).
- `engine/tools/data/kdenliveui-26.08.3.rc`: Kdenliveov fajl menija, preuzet iz izvornog koda Kdenlivea 26.08.3; koristi ga samo provjera pokrivenosti. Ostaje pod Kdenliveovom GPL licencom, a ne pod MIT licencom.

## Licenca

Sopstveni kod projekta Movie Engine objavljen je pod [MIT licencom](../../LICENSE). Kdenlive, MLT, FFmpeg, Node.js paketi i font Poppins zadržavaju svoje licence.
