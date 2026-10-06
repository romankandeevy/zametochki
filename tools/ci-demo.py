#!/usr/bin/env python3
"""Демо-заметка для скриншотов в CI: задачи с напоминанием, канбан-доска и голосовая заметка.
Кладёт её в ~/Library/Application Support/Zametki как обычный JSON-файл заметки."""
import json
import math
import os
import struct
import subprocess
import uuid
import wave

folder = os.path.expanduser("~/Library/Application Support/Zametki")
assets = os.path.join(folder, "Assets")
os.makedirs(assets, exist_ok=True)

# Голосовая заметка: 3 секунды «речи» - синус с плавающей громкостью, сжатый в .m4a.
wav = os.path.join(assets, "demo.wav")
audio = "a1b2c3d4-Голосовая заметка.m4a"
with wave.open(wav, "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(16000)
    frames = bytearray()
    for i in range(48000):
        v = math.sin(i * 0.05) * (0.25 + 0.75 * abs(math.sin(i / 2500)))
        frames += struct.pack("<h", int(v * 20000))
    f.writeframes(bytes(frames))
subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", wav, os.path.join(assets, audio)], check=True)
os.remove(wav)


def card(text):
    return {"id": str(uuid.uuid4()), "text": text}


board = {"columns": [
    {"id": "c1", "title": "Надо сделать", "cards": [card("Сайт"), card("Иконка для Dock")]},
    {"id": "c2", "title": "В работе", "cards": [card("Канбан-доска")]},
    {"id": "c3", "title": "Готово", "cards": [card("Шаблоны"), card("Экспорт в PDF"), card("Режим фокуса")]},
]}

# Строки: (текст, тип, данные предмета). Позиции в UTF-16 - всё здесь из одной плоскости, длины совпадают.
lines = [
    ("Новое в Заметочках", "title", {}),
    ("Всё, что появилось в этой версии.", None, {}),
    ("Задачи", "heading", {}),
    ("Позвонить в студию @завтра 10:00", "todo", {}),
    ("Отправить макеты @пт", "todo", {}),
    ("Обновить README", "done", {}),
    ("Доска", "heading", {}),
    ("￼", "board", {"board": json.dumps(board, ensure_ascii=False)}),
    ("Голосовая заметка", "heading", {}),
    ("￼", "audio", {"audio": audio}),
    ("Расшифровка встаёт строкой под плеером.", None, {}),
    ("", None, {}),
]
text = ""
runs = []
for content, block, extra in lines:
    start = len(text)
    text += content + "\n"
    if block:
        run = {"from": start, "length": len(content) + 1, "block": block}
        run.update(extra)
        runs.append(run)
text = text[:-1]
if runs and runs[-1]["from"] + runs[-1]["length"] > len(text):
    runs[-1]["length"] = len(text) - runs[-1]["from"]

with open(os.path.join(folder, "demo-ci.json"), "w") as f:
    json.dump({"text": text, "runs": runs, "order": -100}, f, ensure_ascii=False, indent=1)
print("demo-ci готова")
