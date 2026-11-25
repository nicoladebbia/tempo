# Tempo — Italian localization (glossary and rules)

English is the development language. Italian (`it`) is the first translation. Strings live in String Catalogs:

| Catalog                                   | Target                   | Holds                                          |
| ----------------------------------------- | ------------------------ | ---------------------------------------------- |
| `Tempo/Tempo/Localizable.xcstrings`       | app                      | every screen, toast, notification, enum name   |
| `Tempo/Tempo/InfoPlist.xcstrings`         | app                      | permission texts (camera, health, location...) |
| `Tempo/Tempo/AppShortcuts.xcstrings`      | app                      | Siri / Shortcuts phrases                       |
| `Tempo/TempoWidget/Localizable.xcstrings` | widget + Live Activities | widget and Live Activity text                  |

Out of scope on purpose (stays English): text that comes from the server or the AI (coach replies, meal plans, backend pushes), the exercise and food databases, `AccountabilityCopy.json`, the Apple Watch app, App Store metadata. See "Not translated" at the end.

## Voice

- Informal "tu". Short, direct, same drill-sergeant tone as the English: imperative verbs, no softeners, no "per favore".
- Sentence case. Italian does not capitalise every word of a title: "Controlla la scheda", not "Controlla La Scheda".
- Keep the English punctuation rhythm (short sentences, full stops, "…" where the English has it). Straight apostrophe `'`.
- Keep numbers, units and `%` placeholders exactly. Never translate `%@`, `%lld`, `%1$@`; reorder with positional specifiers (`%1$@`, `%2$lld`) when Italian word order needs it.
- Italian runs about 20% longer. Reword first, change layout second. Tab labels, chips and buttons: one short word.
- "Tempo" (the app) is never translated. Brand and feature names that stay: Tempo, Whoop, Arena, Lockdown, Focus, RepForge, RecoverIQ, ClutchTime, Pro, XP, PR, RIR, HRV, 1RM, e1RM, kcal.

## Glossary

| English                            | Italian                                                                       | Note                                           |
| ---------------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------- |
| Today                              | Oggi                                                                          | tab                                            |
| Train / Training                   | Allenamento                                                                   | tab and module                                 |
| Fuel                               | Cibo                                                                          | tab and quadrant (nutrition)                   |
| Kitchen                            | Cucina                                                                        | tab                                            |
| Log (verb) / Logged                | Registra / Registrato                                                         | the capture "+" button is "Registra"           |
| Workout                            | allenamento                                                                   | one word everywhere, never "workout"           |
| Session                            | sessione                                                                      |                                                |
| Program (trainer's)                | scheda                                                                        | Italians say "la scheda del trainer"           |
| Plan / Week plan                   | piano / piano settimanale                                                     |                                                |
| Routine                            | routine                                                                       |                                                |
| Set (noun)                         | serie                                                                         | "3 serie da 10"                                |
| Reps                               | ripetizioni (rip. when tight)                                                 |                                                |
| Rest (between sets)                | recupero                                                                      |                                                |
| Rest day                           | giorno di riposo                                                              |                                                |
| Warm-up / Cool-down                | riscaldamento / defaticamento                                                 |                                                |
| Deload                             | scarico                                                                       |                                                |
| Superset / Circuit                 | superset / circuito                                                           |                                                |
| Failure                            | cedimento                                                                     |                                                |
| PR                                 | PR                                                                            | explain as "record personale" when spelled out |
| RIR                                | RIR                                                                           | "ripetizioni in riserva" when spelled out      |
| Streak                             | streak                                                                        |                                                |
| Score / Day score                  | punteggio / punteggio del giorno                                              |                                                |
| Level / XP                         | livello / XP                                                                  |                                                |
| Challenge                          | sfida                                                                         |                                                |
| Friends                            | amici                                                                         |                                                |
| Leaderboard                        | classifica                                                                    |                                                |
| Milestone                          | traguardo                                                                     |                                                |
| Recovery                           | Recupero                                                                      | module and tab                                 |
| Sleep                              | sonno                                                                         |                                                |
| Strain                             | sforzo                                                                        |                                                |
| Readiness                          | prontezza                                                                     |                                                |
| Resting heart rate                 | frequenza cardiaca a riposo                                                   |                                                |
| Body / Mind / Move                 | Corpo / Mente / Movimento                                                     | Today quadrants                                |
| Study                              | Studio                                                                        |                                                |
| Non-negotiables                    | Non negoziabili                                                               |                                                |
| Macros                             | macro                                                                         |                                                |
| Protein / Carbs / Fat / Fiber      | proteine / carboidrati / grassi / fibre                                       |                                                |
| Calories                           | calorie                                                                       | "kcal" stays                                   |
| Meal / Snack                       | pasto / spuntino                                                              |                                                |
| Breakfast / Lunch / Dinner         | colazione / pranzo / cena                                                     |                                                |
| Pantry                             | dispensa                                                                      |                                                |
| Grocery list / Groceries           | lista della spesa / spesa                                                     |                                                |
| Recipe                             | ricetta                                                                       |                                                |
| Supplements                        | integratori                                                                   |                                                |
| Water / Hydration                  | acqua / idratazione                                                           |                                                |
| Barcode / Scan / Receipt           | codice a barre / scansiona / scontrino                                        |                                                |
| Coach / Trainer                    | coach / trainer                                                               |                                                |
| Save / Delete / Edit               | Salva / Elimina / Modifica                                                    |                                                |
| Cancel / Undo                      | Annulla / Annulla                                                             | iOS Italian uses "Annulla" for both            |
| Done / Skip / Next / Back          | Fine / Salta / Avanti / Indietro                                              |                                                |
| Start / Finish / Stop              | Inizia / Concludi / Stop                                                      |                                                |
| Pause / Resume                     | Pausa / Riprendi                                                              |                                                |
| Add / Remove / Close               | Aggiungi / Rimuovi / Chiudi                                                   |                                                |
| Settings / Profile / Notifications | Impostazioni / Profilo / Notifiche                                            |                                                |
| Sign in / Sign out                 | Accedi / Esci                                                                 |                                                |
| Today / Tomorrow / Yesterday       | Oggi / Domani / Ieri                                                          |                                                |
| days / weeks / min / h / s         | giorni / settimane / min / h / s                                              |                                                |
| steps                              | passi                                                                         |                                                |
| Task                               | attività                                                                      | one word everywhere, never "impegno"           |
| Achievement                        | traguardo                                                                     | same as milestone                              |
| Override                           | eccezione                                                                     |                                                |
| Streak                             | streak (feminine: "la streak")                                                | "Streak freeze" = congelamento                 |
| Weight (on a set)                  | carico                                                                        | in prose, "peso"                               |
| Guided run                         | sessione guidata                                                              | a live conditioning coach, not running         |
| Ramp set / Working set             | serie di avvicinamento / serie di lavoro                                      |                                                |
| Review (recap screen)              | riepilogo                                                                     |                                                |
| Debrief                            | resoconto                                                                     |                                                |
| Pace                               | ritmo                                                                         |                                                |
| Accountability                     | disciplina                                                                    |                                                |
| AI                                 | IA                                                                            | "coach IA"                                     |
| Apple Health                       | Salute                                                                        | "Apple Salute" only where the brand is needed  |
| Overdue / Behind / On pace         | in ritardo / indietro / in linea                                              |                                                |
| Ahead / Off track                  | in anticipo / fuori rotta                                                     |                                                |
| Tab (of a screen)                  | sezione                                                                       | never "scheda" (that is the program)           |
| League                             | lega                                                                          | Arena                                          |
| Snooze                             | posticipa                                                                     |                                                |
| Food log                           | diario alimentare                                                             |                                                |
| Nutrition coach                    | coach nutrizionale                                                            |                                                |
| Bodyweight                         | peso corporeo (PC when tight)                                                 |                                                |
| Smith machine / Barbell            | Multipower / bilanciere                                                       |                                                |
| Lift (workout type)                | Sollevamento                                                                  | "alzata" for one lift                          |
| Baseline                           | valori di base                                                                |                                                |
| Levels Recruit ... Mythic          | Recluta, Soldato, Guerriero, Capitano, Comandante, Generale, Leggenda, Mitico |                                                |
| Conditioning                       | condizionamento                                                               |                                                |
| Round / Match                      | giro / partita                                                                |                                                |
| Serving / Servings                 | porzione / porzioni                                                           |                                                |
| Allergens / Additives              | allergeni / additivi                                                          |                                                |
| Ingredients / Label                | ingredienti / etichetta                                                       |                                                |
| Aisle                              | reparto                                                                       | grocery list sections                          |
| Store mode                         | modalità spesa                                                                |                                                |
| Use it up                          | da consumare                                                                  | pantry items close to expiry                   |
| Leftovers / Meal prep              | avanzi / meal prep                                                            |                                                |
| Cut / Maintain / Bulk              | definizione / mantenimento / massa                                            | nutrition goals                                |
| Day type (training / rest)         | tipo di giorno                                                                | "giorno di allenamento", "giorno di riposo"    |
| Fuel setup                         | impostazione di Cibo                                                          | the guided setup of the food tab               |

## Plurals

Counts use catalog plural variations (`one` / `other`) so "1 giorno" and "3 giorni" are both right. English keeps its own `one` / `other` forms, so English output does not change.

## Dates and numbers

- Dates, times and weekdays come from the system locale (`DateFormatter` with no fixed locale, `.formatted(...)`). Fixed `en_US_POSIX` is only for parsing and server formats.
- Display numbers go through `Double.tempoDecimal(_:)` ("1.5" in English, "1,5" in Italian). `String(format:)` stays only for text that is parsed back, exported or sent to a server.

## Adding a string (rule for every future change)

- SwiftUI literals (`Text("…")`, `Button("…")`, `Label("…")`, `.navigationTitle("…")`) are picked up automatically.
- Any other user-visible text needs `String(localized: "…")` (or a `LocalizedStringResource` / `LocalizedStringKey` parameter). Do not build sentences by concatenation; use one string with interpolation.
- Never localise text the program reads back: identifiers, raw values, dictionary keys, analytics names, JSON keys, AI prompts, text sent to the server.
- After adding strings, add the Italian next to the English in the catalog. `LocalizationCatalogTests` fails when a string has no Italian or is stale.

## Not translated (and why)

See the final report of the Italian pass: server and AI text, bundled exercise and food data, `AccountabilityCopy.json`, the Watch app, App Store metadata.
