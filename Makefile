.PHONY: all up down status tools test lint release-good release-bad ai-diagnose ai-canary ai-sec-triage secret-rotate secret-rotate-finish demo demo-auto demo-charts clean help

SHELL := /bin/bash
ROOT_DIR := $(shell pwd)
export PATH := $(ROOT_DIR)/bin:$(PATH)
export PYTHONPATH := $(ROOT_DIR)/ai:$(ROOT_DIR):$(PYTHONPATH)

all: up

## 🚀 Основные команды развертывания (Правило 3 команд)
up: ## Развернуть весь конвейер, секреты, чарты и мониторинг
	@bash scripts/up.sh

down: ## Удалить развернутое окружение
	@bash scripts/down.sh

status: ## Показать статус подов, сервисов и секретов
	@echo "=== Kubernetes Pods ==="
	@kubectl -n demo get pods -o wide 2>/dev/null || echo "Cluster offline / simulated"
	@echo ""
	@echo "=== Encrypted Secrets ==="
	@ls -la secrets/

## 🎬 Демонстрационный стенд для защиты и генерации материалов презентации
demo: ## Интерактивный прогон всех слайдов/этапов для презентации и скриншотов
	@PYTHONPATH=ai:$$PYTHONPATH python3 scripts/demo_suite.py

demo-auto: ## Быстрый сквозной прогон всех слайдов без пауз (90 сек)
	@PYTHONPATH=ai:$$PYTHONPATH python3 scripts/demo_suite.py --auto

demo-charts: ## Сгенерировать интерактивный Grafana RED дашборд с графиками
	@PYTHONPATH=ai:$$PYTHONPATH python3 scripts/demo_suite.py --generate-charts

## 🧪 Тестирование и качество кода
test: ## Запуск unit-тестов с проверкой покрытия (pytest >= 80%)
	@if [ -d ".venv" ]; then \
		PYTHONPATH=. .venv/bin/pytest app/tests/test_main.py --cov=app --cov-report=term-missing -v; \
	else \
		PYTHONPATH=. pytest app/tests/test_main.py --cov=app --cov-report=term-missing -v; \
	fi

lint: ## Линтинг кода (ruff) и валидация Helm-чарта (недостающие ruff/helm ставятся в ./bin)
	@bash scripts/lint.sh

tools: ## Установить инструменты для make lint (helm, ruff) в ./bin (без sudo/apt/pip)
	@bash scripts/install_tools.sh

## 🚦 Canary-релизы и демонстрация автоотката
release-good: ## Запуск успешного канареечного релиза (20% -> 50% -> 100%)
	@bash scripts/canary_deploy.sh good

release-bad: ## Запуск сбойного релиза -> Автооткат -> Запуск AIOps RCA
	@bash scripts/canary_deploy.sh bad

## 🤖 AIOps & LLM Copilot (Ключевое преимущество)
ai-diagnose: ## Запуск AI SRE Incident Analyzer (RCA + diff-патч сбоя)
	@PYTHONPATH=ai python3 ai/incident_analyzer.py

ai-canary: ## Интеллектуальный анализ аномалий Canary-трафика
	@PYTHONPATH=ai python3 ai/canary_evaluator.py 0.04 420.0

ai-sec-triage: ## Интеллектуальный триаж уязвимостей Trivy и авто-патч
	@PYTHONPATH=ai python3 ai/security_triager.py

## 🔐 Управление секретами и zero-downtime ротация
secret-rotate: ## Фаза 1 ротации токена: режим dual-token (старый и новый токен валидны)
	@bash scripts/rotate_secrets.sh

secret-rotate-finish: ## Фаза 2 ротации токена: отзыв старого токена
	@bash scripts/rotate_secrets_finish.sh

clean: ## Очистка временных файлов
	@rm -rf .pytest_cache .coverage .state/rendered-manifests.yaml reports/

help: ## Показать справку по всем командам
	@echo "=========================================================================="
	@echo "🛠️  MTS Cloud DevOps Platform — Доступные команды:"
	@echo "=========================================================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
