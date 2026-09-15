# Память, своп и сон

Lenovo Yoga Book 9 13IRU8: 16 ГБ распаянной RAM, NVMe 1 ТБ, LUKS2 + btrfs.

## Как устроено

| Уровень | Настройка | Откуда |
|---|---|---|
| zram0 | размер = RAM (15.3 ГБ), zstd, приоритет 100 | `/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf` (пакет Omarchy) |
| swapfile | `/swap/swapfile` 15.3 ГБ, btrfs, приоритет 0 | `omarchy-hibernation-setup`, `/etc/fstab` |
| zswap | выключен (`zswap.enabled=0`) | cmdline Omarchy |
| sysctl | swappiness 150, page-cluster 0, watermark_scale_factor 125 | `/etc/sysctl.d/99-omarchy-sysctl.conf` |
| resume | `resume=/dev/mapper/root resume_offset=…` | `/etc/limine-entry-tool.d/resume.conf`, `HOOKS+=(resume)` |

zram — основной своп: zstd сжимает примерно в 3 раза, полностью заполненный
zram занимает около 5 ГБ RAM. Swapfile на диске используется, только если
zram переполнен, и для гибернации.

**Размер swapfile — 16 ГБ, не 32.** Образ гибернации не больше RAM и сжимается
ядром. Замена файла меняет `resume_offset` и требует пересборки UKI; ошибка
молча ломает гибернацию. Выгода от 32 ГБ — только если zram уже переполнен в
момент гибернации, на 16 ГБ RAM это почти не встречается.

Всё перечисленное переживает `omarchy update`: zram и sysctl принадлежат
пакету Omarchy, `/etc/fstab` и cmdline обновление не меняет.

## Крышка: suspend-then-hibernate

На этом ноутбуке доступен только s2idle (`/sys/power/mem_sleep`), он
медленно разряжает батарею. Поэтому при закрытии крышки ноутбук засыпает,
а через 2 часа на батарее уходит в гибернацию. От сети остаётся во сне.
С внешним монитором (clamshell) закрытие крышки по-прежнему ничего не делает.

- [`config/systemd/sleep.conf.d/60-yoga-suspend-then-hibernate.conf`](config/systemd/sleep.conf.d/60-yoga-suspend-then-hibernate.conf)
- [`config/systemd/logind.conf.d/60-yoga-lid.conf`](config/systemd/logind.conf.d/60-yoga-lid.conf)

```bash
bin/yoga-sleep-setup check     # swapfile активен, resume_offset совпадает
bin/yoga-sleep-setup install   # проверка, затем установка в /etc (sudo)
bin/yoga-sleep-setup remove    # вернуть обычный suspend
systemctl hibernate            # один раз проверить, что сеанс восстанавливается
```

`install` ничего не ставит, если `resume_offset` в cmdline не совпадает с
реальным смещением swapfile. `yoga-recovery snapshot` сохраняет обе копии
из `/etc` как справочные файлы; восстанавливать их нужно через `install`.
