# AUDIT.md - Полный аудит проекта Android-WebView-Auto-Builder

**Дата аудита:** 2026-02-04
**Версия проекта:** v0.0.15
**Общая оценка:** 4.5/10

---

## Executive Summary

Проект Android-WebView-Auto-Builder представляет собой инновационное решение для быстрой генерации APK-файлов через бинарное патчинг. Основная идея — отличная, но реализация содержит критические проблемы безопасности и технический долг.

### Статистика проблем

| Приоритет | Количество |
|-----------|------------|
| Критический | 4 |
| Высокий | 6 |
| Средний | 8 |
| Низкий | 5 |

### Ключевые риски
1. **Path Traversal уязвимость** — возможность скачать произвольные файлы с сервера
2. **Секреты в репозитории** — WEBHOOK_SECRET закоммичен в .env
3. **Отсутствие thread-safety** — race conditions в многопользовательском режиме
4. **Нет тестов** — 0% покрытие кода тестами

---

## 1. О проекте

### Назначение
Автоматическая генерация Android APK из любого URL за < 1 секунды через бинарное патчинг шаблона.

### Технологический стек
- **Backend:** Python 3, Flask, Gunicorn
- **Frontend:** HTML/CSS/JavaScript, WebGL (TWGL.js)
- **Build Tools:** Android SDK, OpenJDK 17, zipalign, apksigner
- **Infrastructure:** Docker, docker-compose
- **CI/CD:** GitHub Webhook

### Архитектура
```
User Request → Flask API → UltraFastBuilder → Binary Patching → Signed APK
```

---

## 2. Критические проблемы безопасности

### 2.1 Path Traversal (CRITICAL)

**Файл:** `server.py`
**Строки:** 144-148

```python
def download(filename):
    filepath = os.path.join(OUTPUT_DIR, filename)
    if not os.path.exists(filepath):
        filepath = os.path.join(os.getcwd(), filename)  # ОПАСНО!
```

**Проблема:** Параметр `filename` используется без валидации. Атакующий может запросить `../../../etc/passwd` и получить доступ к файлам за пределами OUTPUT_DIR.

**Рекомендация:**
```python
import os.path

def download(filename):
    # Валидация: только имя файла, без путей
    safe_filename = os.path.basename(filename)
    filepath = os.path.join(OUTPUT_DIR, safe_filename)

    # Проверка что путь внутри OUTPUT_DIR
    if not os.path.realpath(filepath).startswith(os.path.realpath(OUTPUT_DIR)):
        return jsonify({'error': 'Invalid filename'}), 400
```

---

### 2.2 Hardcoded Credentials (CRITICAL)

**Файлы:**
- `CORE/fast_builder.py:94-95, 242`
- `CORE/ultra_fast_builder.py:89-90, 255`

```python
"-storepass", "android", "-alias", "androiddebugkey", "-keypass", "android"
"--ks-pass", "pass:android"
```

**Проблема:** Пароли keystore захардкожены в коде. При компрометации репозитория злоумышленник получает доступ к подписи APK.

**Рекомендация:**
- Вынести пароли в переменные окружения
- Использовать secrets management (Vault, AWS Secrets Manager)
- Для debug-сертификатов — документировать что это intentional

---

### 2.3 Секреты в репозитории (CRITICAL)

**Файл:** `.env`
**Строка:** 2

```
WEBHOOK_SECRET=a7f3b9c2e1d4f6a8b0c5e2d7f9a1b4c6
```

**Проблема:** Реальный секрет webhook закоммичен в репозиторий. Любой с доступом к репо может подделать webhook-запросы.

**Рекомендация:**
1. Удалить `.env` из репозитория: `git rm --cached .env`
2. Добавить `.env` в `.gitignore`
3. Сгенерировать новый секрет
4. Использовать `.env.example` как шаблон

---

### 2.4 Небезопасные WebView настройки (HIGH)

**Файл:** `CORE/linux_mac_build_apk.sh`
**Строки:** 249, 338

```xml
android:usesCleartextTraffic="true"
```

```java
webSettings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
```

**Проблема:**
- Разрешен HTTP-трафик (MITM атаки)
- Смешанный контент разрешен (HTTP на HTTPS странице)

**Рекомендация:**
- Сделать эти настройки конфигурируемыми
- По умолчанию — более безопасные значения
- Документировать риски для пользователей

---

## 3. Проблемы качества кода

### 3.1 Отсутствие валидации входных данных (HIGH)

**Файл:** `server.py`
**Строки:** 106-111

```python
data = request.json
apk_name = data.get('apk_name')
url = data.get('url')

if not apk_name or not url:
    return jsonify({'error': 'Missing parameters'}), 400
```

**Проблемы:**
- Нет проверки формата URL (может быть `javascript:alert()`)
- Нет санитизации имени файла (может содержать `../`)
- Нет ограничений длины
- Нет whitelist символов

**Рекомендация:**
```python
import re
from urllib.parse import urlparse

def validate_url(url):
    parsed = urlparse(url)
    return parsed.scheme in ('http', 'https') and parsed.netloc

def validate_apk_name(name):
    # Только буквы, цифры, пробелы, дефисы, подчеркивания
    return bool(re.match(r'^[a-zA-Z0-9\s_-]{1,50}$', name))

@app.route('/create', methods=['POST'])
def create():
    data = request.json
    apk_name = data.get('apk_name', '').strip()
    url = data.get('url', '').strip()

    if not apk_name or not url:
        return jsonify({'error': 'Missing parameters'}), 400

    if not validate_url(url):
        return jsonify({'error': 'Invalid URL format'}), 400

    if not validate_apk_name(apk_name):
        return jsonify({'error': 'Invalid APK name'}), 400
```

---

### 3.2 print() вместо logging (HIGH)

**Файлы:** Все Python файлы

```python
print(f"Build error: {e}")
print("Initializing Ultra Fast APK Builder environment...")
```

**Проблемы:**
- Нет уровней логирования (DEBUG, INFO, WARNING, ERROR)
- Нет timestamps
- Нет структурированного вывода
- Не работает с logrotate/systemd

**Рекомендация:**
```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Использование:
logger.info("Initializing builder...")
logger.error(f"Build failed: {e}", exc_info=True)
```

---

### 3.3 Generic exception handling (MEDIUM)

**Файл:** `server.py`
**Строки:** 38-40, 68-71

```python
except Exception as e:
    print(f"Failed to initialize builder: {e}")
```

**Проблемы:**
- Ловится слишком широкий Exception
- Теряется stack trace
- Нет различия между типами ошибок

**Рекомендация:**
```python
except (FileNotFoundError, PermissionError) as e:
    logger.error(f"File system error: {e}", exc_info=True)
    raise
except subprocess.CalledProcessError as e:
    logger.error(f"Build tool failed: {e.stderr}")
    raise BuildError(f"Tool execution failed: {e.cmd}")
```

---

### 3.4 Дублирование кода (MEDIUM)

**Файлы:** `CORE/fast_builder.py`, `CORE/ultra_fast_builder.py`

Дублируются:
- `_get_build_tool()` — идентичная логика поиска инструментов
- Логика генерации keystore
- Определение путей к JDK/SDK

**Рекомендация:**
Создать базовый класс или модуль утилит:
```python
# CORE/build_utils.py
class BuildToolResolver:
    def __init__(self, env_dir):
        self.env_dir = env_dir
        self.is_windows = platform.system() == 'Windows'

    def get_tool(self, tool_name):
        # Общая логика поиска
        pass
```

---

### 3.5 Хардкод значений (MEDIUM)

**Локации:**
- `server.py:183` — порт 5000
- `ultra_fast_builder.py:8` — placeholder 50 символов
- `linux_mac_build_apk.sh:58-60` — SDK версии
- `windows_build_apk.ps1:45-47` — SDK версии

**Рекомендация:**
Создать централизованный конфиг:
```python
# config.py
from dataclasses import dataclass
import os

@dataclass
class Config:
    port: int = int(os.getenv('PORT', 5000))
    sdk_version: str = os.getenv('SDK_VERSION', '33')
    build_tools_version: str = os.getenv('BUILD_TOOLS_VERSION', '33.0.1')
    placeholder_length: int = 50
```

---

## 4. Архитектурные проблемы

### 4.1 Race Condition в jobs dict (HIGH)

**Файл:** `server.py`
**Строка:** 24

```python
jobs = {}  # Global dict, no locking
```

**Проблема:** Множественные потоки читают/пишут в dict без синхронизации.

**Рекомендация:**
```python
import threading

jobs_lock = threading.Lock()
jobs = {}

def update_job(job_id, **updates):
    with jobs_lock:
        if job_id in jobs:
            jobs[job_id].update(updates)

def get_job(job_id):
    with jobs_lock:
        return jobs.get(job_id, {}).copy()
```

---

### 4.2 Race Condition при удалении файлов (HIGH)

**Файл:** `server.py`
**Строки:** 82-98

```python
def delete_file_later(filepath, delay=3):
    def delayed_delete():
        time.sleep(delay)
        if os.path.exists(filepath):
            os.remove(filepath)
    threading.Thread(target=delayed_delete).start()
```

**Проблема:** Если скачивание длится > 3 секунд, файл удалится во время передачи.

**Рекомендация:**
```python
# Использовать reference counting или удалять после завершения скачивания
@app.route('/download/<filename>')
def download(filename):
    # ... валидация ...

    def generate():
        with open(filepath, 'rb') as f:
            yield from f
        # Удалить после полной передачи
        os.remove(filepath)

    return Response(generate(), mimetype='application/vnd.android.package-archive')
```

---

### 4.3 God Class Pattern (MEDIUM)

**Файл:** `CORE/ultra_fast_builder.py`

Класс `UltraFastBuilder` делает слишком много:
- Поиск инструментов
- Создание keystore
- Генерация шаблона
- Бинарное патчинг
- Подписание APK

**Рекомендация:**
Разделить на компоненты:
```python
class ToolResolver: pass
class KeystoreManager: pass
class TemplateGenerator: pass
class BinaryPatcher: pass
class ApkSigner: pass

class UltraFastBuilder:
    def __init__(self, tool_resolver, keystore_mgr, template_gen, patcher, signer):
        # Dependency injection
```

---

### 4.4 Отсутствие интерфейса Builder (MEDIUM)

**Проблема:** `UltraFastBuilder` и `FastApkBuilder` не имеют общего интерфейса.

**Рекомендация:**
```python
from abc import ABC, abstractmethod

class ApkBuilder(ABC):
    @abstractmethod
    def prepare_environment(self) -> None:
        pass

    @abstractmethod
    def build(self, url: str, app_name: str, job_id: str,
              progress_callback=None) -> str:
        pass

class UltraFastBuilder(ApkBuilder):
    # Реализация

class FastApkBuilder(ApkBuilder):
    # Реализация
```

---

### 4.5 Фрагментированная конфигурация (MEDIUM)

**Источники конфигурации:**
1. `settings.yaml` — URL и имя APK
2. `.env` — webhook secret, branch
3. Хардкод в Python коде
4. Хардкод в shell скриптах
5. Переменные окружения

**Рекомендация:**
Один источник истины:
```yaml
# config.yaml
server:
  port: 5000
  host: "0.0.0.0"

build:
  sdk_version: "33"
  build_tools_version: "33.0.1"
  package_name: "org.weforks.webview"

security:
  keystore_password: "${KEYSTORE_PASSWORD}"
  webhook_secret: "${WEBHOOK_SECRET}"
```

---

## 5. Отсутствующие практики

### 5.1 Тестирование (CRITICAL)

**Текущее состояние:** 0 тестов

**Необходимо добавить:**
- Unit тесты для билдеров
- Integration тесты для API
- Security тесты для валидации
- Load тесты для concurrency

```python
# tests/test_builder.py
import pytest
from CORE.ultra_fast_builder import UltraFastBuilder

def test_build_creates_apk():
    builder = UltraFastBuilder('/path/to/core')
    result = builder.build('https://example.com', 'TestApp', 'job123')
    assert result.endswith('.apk')
    assert os.path.exists(result)
```

---

### 5.2 Type Hints (MEDIUM)

**Текущее состояние:** Отсутствуют

**Рекомендация:**
```python
from typing import Optional, Callable

def build(
    self,
    url: str,
    app_name: str,
    job_id: str,
    progress_callback: Optional[Callable[[int], None]] = None
) -> str:
    """Build APK with given URL and app name.

    Args:
        url: Target URL to wrap in WebView
        app_name: Display name for the app
        job_id: Unique identifier for this build job
        progress_callback: Optional callback for progress updates (0-100)

    Returns:
        Path to the generated APK file

    Raises:
        BuildError: If build fails
    """
```

---

### 5.3 Документация (LOW)

**Отсутствует:**
- API документация (OpenAPI/Swagger)
- Docstrings в функциях
- Архитектурная документация
- Contribution guide

**Рекомендация:**
- Добавить OpenAPI spec для REST API
- Документировать все публичные методы
- Создать CONTRIBUTING.md
- Добавить архитектурную диаграмму в README

---

## 6. Матрица приоритетов

| # | Проблема | Приоритет | Сложность | Влияние |
|---|----------|-----------|-----------|---------|
| 1 | Path Traversal | CRITICAL | Low | Security breach |
| 2 | .env с секретами | CRITICAL | Low | Security breach |
| 3 | Hardcoded credentials | CRITICAL | Medium | Security |
| 4 | Отсутствие тестов | CRITICAL | High | Quality |
| 5 | Input validation | HIGH | Medium | Security |
| 6 | Race condition jobs | HIGH | Medium | Stability |
| 7 | Race condition delete | HIGH | Medium | UX |
| 8 | print() → logging | HIGH | Low | Observability |
| 9 | WebView security | HIGH | Low | Security |
| 10 | Incomplete requirements.txt | HIGH | Low | Deploy |
| 11 | Code duplication | MEDIUM | Medium | Maintainability |
| 12 | God class | MEDIUM | High | Maintainability |
| 13 | Config fragmentation | MEDIUM | Medium | Maintainability |
| 14 | No Builder interface | MEDIUM | Medium | Extensibility |
| 15 | Hardcoded values | MEDIUM | Low | Configurability |
| 16 | Type hints | MEDIUM | Medium | Maintainability |
| 17 | Generic exceptions | MEDIUM | Low | Debugging |
| 18 | No docstrings | LOW | Low | Documentation |
| 19 | No API docs | LOW | Medium | Documentation |

---

## 7. Рекомендуемый план действий

### Фаза 1: Критические исправления (1-2 дня)
1. [ ] Исправить Path Traversal в `server.py`
2. [ ] Удалить `.env` из репозитория
3. [ ] Добавить валидацию входных данных
4. [ ] Добавить `requests` в `requirements.txt`

### Фаза 2: Высокоприоритетные улучшения (3-5 дней)
1. [ ] Заменить print() на logging
2. [ ] Добавить thread locks для jobs
3. [ ] Исправить race condition при удалении файлов
4. [ ] Сделать WebView настройки конфигурируемыми

### Фаза 3: Среднеприоритетные улучшения (1-2 недели)
1. [ ] Создать базовый класс/интерфейс Builder
2. [ ] Устранить дублирование кода
3. [ ] Централизовать конфигурацию
4. [ ] Добавить type hints

### Фаза 4: Качество кода (ongoing)
1. [ ] Написать unit тесты
2. [ ] Написать integration тесты
3. [ ] Добавить docstrings
4. [ ] Создать API документацию

---

## 8. Заключение

Проект Android-WebView-Auto-Builder имеет отличную core-идею (бинарное патчинг для мгновенной генерации APK), но страдает от типичных проблем быстрого прототипирования:

**Сильные стороны:**
- Инновационный подход к генерации APK
- Простой и понятный API
- Хорошая поддержка разных платформ
- Рабочий Docker deployment

**Слабые стороны:**
- Критические уязвимости безопасности
- Отсутствие тестов
- Технический долг в архитектуре
- Фрагментированная конфигурация

Рекомендуется немедленно устранить критические проблемы безопасности перед production использованием.

---

*Аудит выполнен: 2026-02-04*
*Инструменты: статический анализ кода, ручной review*
