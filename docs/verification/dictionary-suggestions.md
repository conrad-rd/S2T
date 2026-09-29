# Dictionary correction learning

After successful delivery, S2T watches the receiving nonsecure editor for one minute. It copies exact changed spans locally, including numbers, joined words and preserved internal spacing. Each candidate carries at most 480 characters of nearby text from the delivered passage after editing. Unchanged surrounding document text is not sent.

Settings → Writing → Dictionary offers **Categorize corrections with Jev**, off by default, including for existing users. Word detection and saving run locally without a key, credits or model request. When enabled, categorization uses one explicitly selected connection: Jev key through TypeSafe, OpenRouter key, or S2T credits. The choice is independent of speech, cleanup and the optional Jev cleanup setting. Missing credentials and provider failures leave the saved correction intact and appear in the dictionary status. No account fallback is used.

The observer samples at 50 ms and detects text stable for 200 ms. The controller immediately saves the exact correction with its usage context and shows the four-second confirmation. Only then, if enabled, it waits another 600 ms before requesting categories. Jev's correction-confidence question and 100 category questions run in three batches of at most 49. Categorization requires correction confidence of at least 0.98 and category membership of at least 0.80; it keeps the strongest qualifying category. A rejected, uncertain, unclassified or failed result never removes the locally saved word. These cutoffs are policy choices, not measured accuracy guarantees.

Sampling continues during categorization. Text changes invalidate pending category decisions, and the controller rechecks generation, cancellation, field/app focus, exact current text and the deadline before applying a response. Further typing preserves saved original/replacement pairs. Undo removes records created in this session; explicit Remove suppresses the original for the rest of the session. Metadata updates do not restart an existing confirmation's timer or show it again after expiry. A failed local save cannot produce a successful-save status.

The destination capture records the insertion selection and a bounded pre-insertion field snapshot while transcription/processing continues. The observer uses the selection to distinguish repeated text. If a correction is already present in its first sample, the known surrounding text anchors it, including replacements of a different length. Unchanged pre-paste text and older occurrences elsewhere in the field cannot be mistaken for an early correction.

Network transport failures retry the failed batch twice with bounded backoff. Successful batches are not repeated within that evaluation. S2T requests derive their idempotency key from the session and exact request content, so credit retries replay existing work. Cancellation stops local processing; already submitted provider work may still incur its normal charge. No alternate model or account is silently used.

Generated records retain the replacement, `Replaces`, `Context` and `Categories`. Existing context is never stripped on read. Records deduplicate by original, replacement and context across launches, preserving existing categories when categorization is off. Revised/undone session records are removed only when their generated contents still match, preserving manual edits. Normal cleanup and optional Jev cleanup receive the saved contexts and category definitions as reference data, with instructions against global substitutions or inserting the usage example. The editable dictionary rows show the original, context and category labels; search includes them.

The confirmation remains the compact nonactivating dark capsule, with a four-second expiry and first-click Remove. It appears only after persistence succeeds. No screen inspection or microphone use is involved in learning.

## Limits

Accessibility must expose the receiving text and focus reliably. Reads stay off the main thread and exclude secure, ambiguous and oversized fields. When focus points to a descendant inside an editor, a bounded ancestor walk resolves that same editor and checks its secure ancestors before reading. The field limit remains 16 KB and the dictionary file limit 64 KB. Temporary focus changes or unavailable reads pause observation; returning to the original editor resumes it within the one-minute deadline. A new recording or cancellation ends the session. Edits completed after that deadline cannot be observed. Early edits require a readable pre-insertion snapshot when the delivered text has already changed. Unsupported edits require manual dictionary entry; unavailable or uncertain categorization leaves the local correction uncategorized. This workflow cannot promise 100 percent recognition, interpretation or cross-application coverage.

## Verification

- `S2T_DICTIONARY_REQUEST_FIXTURE=/private/tmp/s2t-dictionary-requests.json bash scripts/test.sh` runs domain/service tests and exports synthetic native decision requests for the gateway check.
- `node billing-local/dictionary-learning-check.mjs /private/tmp/s2t-dictionary-requests.json` runs those actual native requests through the existing policy, mock OpenRouter provider, encrypted in-memory ledger, credit replay and account isolation.
- `node --test billing-local/tests/jev.test.mjs` verifies settlement and invalid provider response handling.
- `build/S2T.app/Contents/MacOS/S2T --verify-dictionary` verifies injected AX fixtures, secure/oversized exclusions, real controller cancellation and focus races with delayed fake Jev replies, keyless native word editing, save-before-categorization, default-off preferences, undo, temporary files, hidden confirmation layout, Remove and the real four-second timer.
- `--verify-models`, `--verify-jev`, `--verify-writing`, `--verify-api-keys` and `--verify-build` cover observation, cleanup routing, editable dictionary rows, key separation and the packaged identity.

All checks use synthetic text and fake providers. They do not read real fields, dictionaries, keys or clipboard contents, make live provider calls, or capture screen pixels. Live Jev semantic accuracy and receiving-app Accessibility compatibility are not established by these tests.

## Category vocabulary

Category IDs are permanent. The vocabulary lives in `Sources/S2TCore/DictionaryLearning.swift`.

- `c001`: Given names
- `c002`: Family names
- `c003`: Full personal names
- `c004`: Nicknames and usernames
- `c005`: Honorifics and titles
- `c006`: Company names
- `c007`: Product and brand names
- `c008`: Team and department names
- `c009`: Organizations and institutions
- `c010`: Project and internal code names
- `c011`: Countries and regions
- `c012`: Cities and towns
- `c013`: Streets and addresses
- `c014`: Buildings and landmarks
- `c015`: Geographic and natural features
- `c016`: Languages and dialects
- `c017`: Nationalities and cultures
- `c018`: Travel and tourism
- `c019`: Transport and vehicles
- `c020`: Hotels and accommodation
- `c021`: Cloud services
- `c022`: Artificial intelligence
- `c023`: Software applications
- `c024`: Programming languages
- `c025`: Frameworks and libraries
- `c026`: APIs and integrations
- `c027`: Databases and storage
- `c028`: Operating systems
- `c029`: Computer hardware
- `c030`: Networking and DNS
- `c031`: Cybersecurity
- `c032`: Web development
- `c033`: Mobile development
- `c034`: Developer tools
- `c035`: Software testing
- `c036`: DevOps and deployment
- `c037`: Data science and analytics
- `c038`: Mathematics and statistics
- `c039`: Scientific research
- `c040`: Engineering
- `c041`: Sales
- `c042`: Marketing
- `c043`: Advertising
- `c044`: Customer support
- `c045`: Customer success
- `c046`: Business strategy
- `c047`: Business operations
- `c048`: Project management
- `c049`: Product management
- `c050`: Entrepreneurship
- `c051`: Finance and accounting
- `c052`: Banking and payments
- `c053`: Investing and securities
- `c054`: Insurance
- `c055`: Taxes
- `c056`: Legal terms and contracts
- `c057`: Compliance and regulation
- `c058`: Human resources
- `c059`: Recruiting and careers
- `c060`: Real estate
- `c061`: Medicine and healthcare
- `c062`: Medication and pharmacy
- `c063`: Anatomy and physiology
- `c064`: Mental health
- `c065`: Fitness and exercise
- `c066`: Nutrition
- `c067`: Biology and genetics
- `c068`: Chemistry
- `c069`: Physics and astronomy
- `c070`: Environment and sustainability
- `c071`: Education and teaching
- `c072`: Academic subjects and courses
- `c073`: Books and publishing
- `c074`: Writing and grammar
- `c075`: Translation
- `c076`: History
- `c077`: Philosophy and religion
- `c078`: Politics and government
- `c079`: Journalism and news
- `c080`: Social sciences
- `c081`: Music and audio
- `c082`: Film and television
- `c083`: Photography
- `c084`: Visual art and design
- `c085`: Animation and video production
- `c086`: Games and gaming
- `c087`: Sports
- `c088`: Fashion and clothing
- `c089`: Beauty and personal care
- `c090`: Events and entertainment
- `c091`: Food and cooking
- `c092`: Drinks
- `c093`: Shopping and retail
- `c094`: Home and household
- `c095`: Family and relationships
- `c096`: Pets and animals
- `c097`: Hobbies and crafts
- `c098`: Dates and scheduling
- `c099`: Measurements and quantities
- `c100`: Everyday language

## Verified package, September 21

S2T 1.0.1, Build 729 at build/S2T.app. All 430 Swift tests passed. The three Jev billing tests and actual-native-request gateway/ledger check passed. Packaged dictionary, models, Jev, Writing, API-key and build probes passed. The cancelled-request resubmission regression was reproduced before the fix and passed afterward. No live semantic-accuracy test was performed. The running app was not restarted.


## Verified correction fixes, September 22

S2T 1.0.1, Build 781 at build/S2T.app. Reproduced two failures before their fixes: a focused text descendant prevented observation, and later context changes removed an approved entry before the replacement judgment finished. The packaged dictionary probe now verifies ancestor resolution, secure-ancestor exclusion, persistence during context changes, uncertain follow-up decisions and undo. New records select the strongest qualifying category; existing multi-category records remain supported.

All 447 Swift tests passed. The native-request gateway/ledger check and all three Jev billing tests passed. Packaged dictionary, models, Jev, Writing, API-key and build probes passed. CLAUDE.md remains linked to AGENTS.md.

The user reported T3 Code. Read-only inspection of the installed T3 Code Nightly application bundle found its ComposerPromptEditor uses ProseMirror with role textbox. The existing T3 browser geometry fixture records AXTextArea. The focused-descendant regression covers a compatible editor structure, but it does not prove the precise live failure in T3 Code. No live fields, credentials, inference, microphone or screen pixels were accessed. The running app was preserved; restart S2T to load the updated executable.


## Verified local learning and optional categorization, September 26

S2T 1.0.1, Build 901 at build/S2T.app. The packaged dictionary and build-identity probes passed. The hidden Writing UI probe and the native-request credit gateway check also passed. All 34 focused dictionary tests passed against the actual core sources in an isolated temporary package. Initial full-workspace checks encountered unrelated prompt/speech source edits in progress; the release was built from a frozen copy of the current sources, and all dictionary implementation files were compared with that snapshot afterward.

Reproduced before fixing: a detected correction remained unsaved while waiting for Jev; a pending paste attached to an older occurrence instead of the recorded insertion point; and local saving duplicated a previously categorized entry. Verification covers keyless native word editing through observation, persistence and confirmation; default-off preference migration; changed-length early edits; undo; stale/focus-lost replies; uncertain categories and provider failures; all three independent connections; and category updates after confirmation expiry. The final packaged probe measured 10.6 ms for a local save and hidden confirmation construction. Observer settling remained 200 ms. These are synthetic local measurements, not a cross-application latency guarantee.

One initial packaged run failed the existing four-second dismissal timing assertion immediately after compilation. The identical packaged probe passed on retry, including real timer dismissal; no timer assertion was weakened. Provider calls used mocks. Live Jev semantic accuracy and external-editor Accessibility coverage were not tested. The running app was not restarted.
