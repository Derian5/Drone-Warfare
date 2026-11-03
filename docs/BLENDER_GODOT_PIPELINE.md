# Деревянный шар: Blender → glTF/GLB → Godot

## 1. Результат и расположение файлов

Модель создана в **открытом локальном Blender 5.2.3 LTS**, через аддон Blender MCP. Импорт проверен в **Godot 4.7.2**.

| Файл | Назначение |
| --- | --- |
| `art_source/wooden_sphere/wooden_sphere.blend` | Исходная сцена Blender: шар, студия, запечённый материал и сохранённый процедурный материал |
| `models/wooden_sphere/wooden_sphere.glb` | Готовая модель для Godot со встроенными текстурами |
| `models/wooden_sphere/textures/wood_basecolor.png` | Запечённый цвет древесины, 1024×1024, sRGB |
| `models/wooden_sphere/textures/wood_normal.png` | Запечённая tangent-space normal map, 1024×1024, Non-Color |
| `models/wooden_sphere/pipeline_report.json` | Версия Blender, геометрия и пути результатов |
| `tools/blender/create_wooden_sphere.py` | Воспроизводимый скрипт создания, запекания и экспорта |
| `tools/blender/verify_import.gd` | Проверка реально импортированных материалов, UV и узла в `main.tscn` |

Параметры шара: радиус **1 м**, диаметр **2 м**, 1986 вершин в Blender, **3968 треугольников**, один материал. После экспорта число render-вершин может увеличиться из-за разделения UV-шва — это нормально.

Папка исходника содержит `.gdignore`: Godot не импортирует её как вторую игровую модель. Для игры используется явный экспорт `.glb`.

## 2. Как увидеть модель сейчас

### В Godot

1. Открой `main.tscn`.
2. Переключись на вкладку **3D** вверху редактора. Корень сцены — `Control`, поэтому редактор может первоначально открыть вкладку 2D.
3. В дереве сцены выбери **WoodenSpherePreview → WoodenSphere**.
4. Наведи мышь на 3D-окно и нажми **F** — редактор сфокусируется на модели.

Шар добавлен обычным сохранённым узлом сцены, а не создаётся кодом в `_ready()`. Поэтому его видно до запуска игры. Группа `WoodenSpherePreview` расположена в `(-3.3, 0, 2.2)`, рядом с существующей ракетой, и содержит два источника света для просмотра материала.

Нижняя точка экспортированного шара находится на Y=0: его центр в Blender был поднят на Z=1, а glTF преобразовал Z-up в Y-up. Для просмотра шара запуск F5 не требуется — это объект основной сцены редактора, не новый игровой юнит.

### В Blender

Открой `art_source/wooden_sphere/wooden_sphere.blend`. Выбери `WoodenSphere`, затем нажми **Numpad .** (Frame Selected) и включи **Material Preview** клавишей **Z → M**.

В материале `Wood_Baked_PBR` стоят готовые текстуры. В списке материалов также сохранён `Wood_Procedural_Source` — исходный узловой материал, из которого они запекались.

## 3. Устройство локального MCP-подключения

В этой работе использована цепочка:

```text
MCP-клиент
    ↓ initialize / tools/list / tools/call, JSON-RPC 2.0 по stdio
tools/blender/mcp_server.py
    ↓ локальный TCP 127.0.0.1:9876
официальный аддон Blender MCP
    ↓ выполнение Python в главном потоке открытого Blender
bpy: геометрия → материал → bake → экспорт
```

Аддон взят из https://github.com/ahujasid/blender-mcp, зафиксированный commit:
`992233bb258975a05eec8b5691465c50c2831e34`.

Для этой задачи используется небольшой MCP-адаптер проекта на стандартной библиотеке Python. Он предоставляет только `get_scene_info` и `execute_blender_code`; установка `uv`, SDK MCP и пакетов генерации моделей не понадобилась.

### Подключение после перезапуска Blender

1. **Edit → Preferences → Add-ons**: включи **MCP for Blender**.
2. В 3D-окне нажми **N**, открой вкладку **MCP for Blender**.
3. Убедись, что сервер запущен на **9876**. В зависимости от версии кнопка называется **Start MCP Server** или **Connect to Claude**; название не ограничивает используемый MCP-клиент.
4. Из корня проекта проверь:

   ```powershell
   python tools/blender/mcp_client.py
   ```

   Клиент выполнит MCP-handshake и выведет сведения о текущей сцене.

В `opencode.json` добавлен сервер `blender-local`. Чтобы инструменты появились непосредственно в OpenCode, **открой именно папку Drone Warfare как проект и полностью перезапусти OpenCode**. Конфигурация не подхватывается уже работающей сессией. В текущей работе MCP-запросы выполнены одноразовым клиентом `mcp_client.py`, без необходимости прерывать сессию.

Если проект перемещается на другой диск или компьютер, обнови абсолютный путь к `tools/blender/mcp_server.py` в массиве `command` файла `opencode.json`.

## 4. Ручное создание геометрии в Blender

1. **Add → Mesh → UV Sphere**.
2. Сразу после создания открой панель последней операции (**F9**):
   - Segments: **64**;
   - Rings: **32**;
   - Radius: **1**.
3. В **Scene Properties → Units** выбери **Metric**, Unit Scale **1.0**.
4. У шара установи Location **(0, 0, 1)**. Это поднимает его на пол, но не меняет радиус.
5. Если вручную менял масштаб или поворот: **Ctrl+A → Rotation & Scale**.
6. Правой кнопкой по шару → **Shade Smooth**.
7. В **Object Data Properties → UV Maps** проверь наличие `UVMap`. У UV Sphere она создаётся автоматически. Для произвольной модели её нужно создать в Edit Mode через UV Unwrap.

UV нужны, чтобы каждая точка поверхности получала цвет из соответствующего участка PNG. Без UV запечённая текстура не сможет корректно лечь на модель.

## 5. Процедурный материал дерева

В **Shading** создай материал на **Principled BSDF**:

- Metallic: **0**;
- Roughness: **0.58**.

Использованный узловой граф:

```text
Texture Coordinate: Generated
    → Vector Math: Subtract (0.5, 0.5, 0.5)
    → Vector Math: Multiply (2.0, 2.0, 0.35)
        ├→ Wave Texture: Rings, Z → Fac ─┐
        └→ Noise Texture → Fac ──────────┤
                                        ↓
                              Mix Color: Multiply
                                ├→ Color Ramp → Principled Base Color
                                └→ Bump Height → Principled Normal
```

Настройки:

| Узел | Значения |
| --- | --- |
| Wave Texture | Rings / Z; Scale 5; Distortion 3.2; Detail 3; Detail Scale 1.5 |
| Noise Texture | Scale 48; Detail 2; Roughness 0.7 |
| Mix Color / Multiply | Factor 0.35 |
| Color Ramp | От тёмно-коричневого через ореховый к светлому золотистому |
| Bump | Strength 0.22; Distance 0.035 |

В Blender процедурные узлы вычисляют рисунок во время отображения. **glTF не переносит произвольный граф Wave/Noise/Color Ramp.** Поэтому следующий этап — преобразование результата этого графа в текстуры.

## 6. Запекание Base Color

1. Переключи Render Engine на **Cycles**. Для этого примера использовался CPU, Samples **8**.
2. В материале добавь **Image Texture → New**:
   - Name: `wood_basecolor`;
   - Width / Height: **1024**;
   - Color Space: **sRGB**.
3. Этот узел пока **не подключай** к Base Color: исходным цветом всё ещё должен быть процедурный граф.
4. Выдели узел Image Texture, чтобы он стал активной целью запекания.
5. Выдели шар и сделай его активным объектом.
6. **Render Properties → Bake**:
   - Type: **Diffuse**;
   - Contributions: включён только **Color**;
   - **Direct** и **Indirect** выключены;
   - Margin: **16 px**.
7. Нажми **Bake**.
8. В Image Editor: **Image → Save As**, сохрани `wood_basecolor.png`.

Отключение Direct/Indirect важно: текстура должна содержать цвет дерева, а не тени и освещение студии. Освещение затем рассчитает Godot.

## 7. Запекание Normal Map

1. Добавь второй **Image Texture → New**:
   - Name: `wood_normal`;
   - Size: **1024×1024**;
   - Color Space: **Non-Color**.
2. Сделай именно этот Image Texture активным.
3. В исходном материале Bump всё ещё должен быть подключён к Principled Normal.
4. **Bake → Type: Normal**, Space: **Tangent**, стандартные оси **+X / +Y / +Z**.
5. Нажми **Bake**, затем сохрани `wood_normal.png`.

Normal map хранит направления для мелкого рельефа, а не цвет, поэтому ей нужен **Non-Color**. Она создаёт видимые волокна без увеличения числа полигонов. В этом пайплайне используется соглашение +Y, совместимое с glTF/Godot, без ручного переворачивания зелёного канала.

## 8. Материал для экспорта

Создай второй материал `Wood_Baked_PBR` и назначь его шару:

```text
wood_basecolor.png [sRGB] ─────────────────→ Principled Base Color
wood_normal.png [Non-Color] → Normal Map ──→ Principled Normal
Principled BSDF ──────────────────────────→ Material Output
```

- Normal Map: Tangent Space, Strength **0.75**.
- Metallic: **0**.
- Roughness: **0.58**.

Отдельная roughness-карта здесь не требуется: шероховатость постоянная. Сохрани процедурный материал с Fake User, чтобы его можно было снова назначить для редактирования и повторного bake.

Сохрани исходник `.blend`. Чтобы PNG сохранялись и внутри исходника: **File → External Data → Pack Resources**. Это упаковка ресурсов в `.blend`, отдельная от встраивания текстур в GLB.

## 9. Экспорт GLB

1. Перейди в Object Mode и выдели **только шар**.
2. **File → Export → glTF 2.0**.
3. Выбери:
   - Format: **glTF Binary (.glb)**;
   - Include → **Selected Objects**;
   - UVs / Normals: включены;
   - Materials: **Export**;
   - Transform → **+Y Up**: включено;
   - Apply Modifiers: включено, если используются модификаторы.
4. Сохрани в `models/wooden_sphere/wooden_sphere.glb`.

GLB содержит геометрию, UV, PBR-материал и изображения внутри одного файла. Студийные камера, пол и свет не экспортируются благодаря Selected Objects. Поворот на −90° вручную не нужен: экспортёр сам преобразует Blender Z-up в glTF/Godot Y-up.

## 10. Импорт в Godot

1. Помести GLB в папку проекта, например `models/wooden_sphere/`.
2. Дождись завершения импорта.
3. Двойной щелчок по файлу открывает Advanced Import Settings. Проверь Mesh и материал, затем при необходимости нажми Reimport.
4. Перетащи `.glb` из FileSystem в свою сцену — получится экземпляр импортированного `PackedScene`.
5. Для позиции, света и дополнительных игровых компонентов используй родительский **Node3D** в собственной `.tscn`.
6. Сохрани `.tscn`.

Для этой модели структура в `main.tscn`:

```text
DroneWarfare (Control)
├── Rocket                         ← существующая модель
└── WoodenSpherePreview (Node3D)
    ├── WoodenSphere               ← экземпляр wooden_sphere.glb
    ├── KeyLight (OmniLight3D)
    └── FillLight (OmniLight3D)
```

Импортёр Godot извлёк встроенные изображения также в файлы `wooden_sphere_wood_basecolor.png` и `wooden_sphere_wood_normal.png` рядом с GLB. Это результат импорта. PNG в `textures/` — оригиналы запекания из Blender. Файлы `.import` хранят настройки импорта; папка `.godot/` — пересоздаваемый кеш.

## 11. Изменения и повторный экспорт

1. Открой исходный `.blend`.
2. Для изменения рисунка назначь шару `Wood_Procedural_Source`, поправь Wave/Noise/Color Ramp.
3. Повтори bake обоих изображений в их активные Image Texture-узлы и сохрани PNG.
4. Верни шару `Wood_Baked_PBR`, убедись, что он использует обновлённые изображения.
5. Экспортируй только шар в тот же GLB.
6. Godot обнаружит изменение и переимпортирует файл; экземпляр в `main.tscn` останется на месте.

Если меняется только Roughness, геометрия или масштаб, повторно запекать цвет не нужно. Если изменилась UV-развёртка, изображения нужно запечь заново.

Для автоматического повторения **нового** ассета:

```powershell
python tools/blender/mcp_client.py --script tools/blender/create_wooden_sphere.py
```

Перед повтором измени `ASSET` на новое имя, например `wooden_sphere_v2`. Скрипт специально отказывается перезаписывать существующий GLB или исходник. При переносе проекта также поправь `PROJECT` в скрипте.

## 12. Проверка результата

Из корня проекта:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tools/blender/verify_import.gd
```

Проверены: загрузка GLB, один экспортированный меш, PBR-материал, обе текстуры, размер Base Color, UV, диаметр 2 м, узел в `main.tscn` и сохранность существующего узла Rocket. Результат при создании: **14 проверок, 0 ошибок**.

### Типичные причины неправильного вида

| Симптом | Что проверить |
| --- | --- |
| В Godot белый шар | Назначен ли перед экспортом image-based материал вместо процедурного? Подключён ли Image Texture к Base Color? |
| Bake чёрный или не работает | Активен ли нужный Image Texture? Выделен ли шар? Есть ли UV? Выбран ли Cycles? |
| Цвет уже содержит тени | В Diffuse Bake должны быть выключены Direct и Indirect |
| Странные блики от normal map | У normal — Non-Color; подключение через Normal Map, а не прямо к Normal |
| Модель не видна в редакторе | Открыта ли вкладка 3D? Выбери WoodenSphere и нажми F |
| После изменения всё выглядит по-старому | Сохрани PNG, экспортируй GLB заново и дождись Reimport |
| Модель отличается по яркости от Blender | Сравни освещение, world/environment, roughness и тональное отображение; они не входят в материал как готовый рендер |

## 13. Документация

- Blender MCP: https://github.com/ahujasid/blender-mcp
- Blender glTF exporter: https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html
- Blender texture baking: https://docs.blender.org/manual/en/latest/render/cycles/baking.html
- Godot importing 3D scenes: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html
