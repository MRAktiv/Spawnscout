# Spawnscout

Spawnscout shows where players of your level are gaining experience fastest right now and how crowded those spots are.

Mobs in Forever belong to whoever tags them first, so a popular spot can be full long before you get there. Spawnscout collects live reports from other players with the addon and shows you the spots that are worth the trip.

## Features

- **Live spots.** Reports from the last 15 minutes by players within two levels of you, sorted by experience per hour.
- **Crowding at a glance.** Green: fewer than 25% of the mobs around are tagged by others. Yellow: fewer than 50%. Red: more. Grey: unknown. Spots in another layer are shown faded.
- **World map dots.** Spots appear on the world map. Click a dot, or a row in the window, to set a waypoint.
- **Your own rate.** The window shows your experience per hour from kills. Quest turn-ins are not counted, and the rested bonus is taken out so that rates stay comparable.

## Commands

- `/spawnscout` or `/sscout`: open the "Where it is free" window. The minimap button does the same; right-click it for options, Shift + left click to hide or show the map dots.
- `/spawnscout diag`: open a diagnostic report. Please copy it into your bug report.

Crowding is measured from enemy nameplates, so they need to be turned on. If they are off, the window offers a "Turn on" button.

## What the addon shares

Spawnscout exchanges data with other copies of the addon through a hidden chat channel, with no external servers.

- **Spot report**, every 2 minutes while you are killing mobs (at least 3 kills): zone, coordinates of your farming spot, layer, level, experience per hour, share of tagged mobs, number of free mobs in view, number of kills and your faction.
- The coordinates are the average of your kill positions, not where you stand, so a dot never appears at a quest giver.
- No report is sent inside dungeons, during flights or when you are not killing.
- Reports from the other faction are dropped, so players of the other faction do not see your spots, and you do not see theirs.
- The report contains no name, and the addon neither stores nor shows names. The game itself attaches the sender's name to every addon message, so someone running their own code in the same channel could see who sent a report.
- You can turn sharing off in the options. You will still see other players' spots, but they will not see yours.
- Only your settings are saved to disk. Reports from other players are kept in memory and dropped after 15 minutes.

## Good to know

- Spots appear only where other Spawnscout users are fighting near your level.
- Languages: English and Russian.

## На русском

Spawnscout показывает, где игроки вашего уровня сейчас быстрее всего получают опыт и насколько там тесно.

В Forever моб достаётся тому, кто тегнул его первым, поэтому популярное место бывает занято задолго до вашего прихода. Spawnscout собирает свежие отчёты других игроков с аддоном и показывает места, куда стоит идти.

**Возможности**

- Места из отчётов за последние 15 минут от игроков в пределах двух уровней от вас, лучшие по опыту в час идут первыми.
- Цвет показывает тесноту: зелёный, если другие тегнули меньше 25% мобов вокруг, жёлтый, если меньше 50%, красный, если больше, и серый, если неизвестно. Места в другом слое бледнее.
- Точки на карте мира. Щелчок по точке или по строке окна ставит метку.
- Свой опыт в час за убийства. Сдача заданий не учитывается, а бонус отдыха вычитается, чтобы цифры можно было сравнивать.

**Команды:** `/spawnscout` или `/sscout` открывает окно "Где свободно", кнопка у миникарты делает то же, правый щелчок по ней открывает настройки, а Shift + левый щелчок скрывает и возвращает точки на карте, `/spawnscout diag` открывает отчёт для сообщения об ошибке. Тесноту аддон измеряет по полоскам над головами противников, поэтому они должны быть включены; если они выключены, окно предложит кнопку "Включить".

**Что передаётся.** Обмен идёт через скрытый канал чата, без внешних серверов. Пока вы убиваете мобов (от трёх убийств), раз в 2 минуты уходит отчёт: зона, координаты места фарма, слой, уровень, опыт в час, доля занятых мобов, число свободных мобов в поле зрения, число убийств и фракция. Координаты считаются по местам убийств, а не по тому, где вы стоите, поэтому точка не появится у NPC с заданиями. В подземельях, в полёте и без убийств отчёт не уходит. Отчёты другой фракции аддон отбрасывает: игроки другой фракции не видят ваших мест, а вы их. Имени в отчёте нет, аддон имена не хранит и не показывает, но игра сама прикладывает имя отправителя к каждому сообщению аддона, и игрок со своим кодом в том же канале может увидеть, кто отправил отчёт. Отправку можно выключить в настройках: вы будете видеть других, а они вас нет. На диск пишутся только настройки, а чужие отчёты хранятся в памяти и стираются через 15 минут.

**Полезно знать:** места появляются только там, где рядом по уровню сражаются другие игроки со Spawnscout. Языки: русский и английский.

## License

Copyright (c) 2026 MRAktiv. All rights reserved, see [LICENSE](LICENSE). The libraries in `Libs` belong to their authors and keep their own licenses.
