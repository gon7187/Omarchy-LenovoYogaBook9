# Изменения

## 2026-09-27 — стабильное чтение потока INGENIC

`bin/yoga-sensor-keepalive`, `config/systemd/yoga-sensor-keepalive.service`:
открытие порта с `O_NOCTTY` и raw-режимом устраняет интерпретацию бинарных данных
как SIGQUIT/EOF, включая гонку при запуске. Добавлен безопасный тест на PTY.
