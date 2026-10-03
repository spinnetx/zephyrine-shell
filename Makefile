# Makefile — Сборка и системная установка оболочки Zephyrine

PREFIX ?= /usr
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/zephyrine
DATADIR ?= $(PREFIX)/share/zephyrine
SESSIONSDIR ?= $(PREFIX)/share/wayland-sessions
APPLICATIONSDIR ?= $(PREFIX)/share/applications
SDDMTHEMESDIR ?= $(PREFIX)/share/sddm/themes

.PHONY: all install uninstall user-install user-uninstall test clean

all:
	@echo "Zephyrine Shell готов к установке."
	@echo "Для установки в систему запустите: sudo make install"
	@echo "Для установки в ~/.local запустите: make user-install"

install:
	@echo "==> Установка Zephyrine Shell в $(DESTDIR)$(PREFIX)..."
	
	# Создание каталогов
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(LIBDIR)/scripts
	install -d $(DESTDIR)$(DATADIR)/quickshell
	install -d $(DESTDIR)$(DATADIR)/settings
	install -d $(DESTDIR)$(DATADIR)/hypr
	install -d $(DESTDIR)$(DATADIR)/themes
	install -d $(DESTDIR)$(DATADIR)/assets
	install -d $(DESTDIR)$(SESSIONSDIR)
	install -d $(DESTDIR)$(APPLICATIONSDIR)
	install -d $(DESTDIR)$(SDDMTHEMESDIR)/zephyrine

	# Исполняемые файлы
	install -m 755 bin/zephyrine-session $(DESTDIR)$(BINDIR)/zephyrine-session
	install -m 755 bin/zephyrine-settings $(DESTDIR)$(BINDIR)/zephyrine-settings
	install -m 755 bin/zephyrine-wallpaper-desktop $(DESTDIR)$(BINDIR)/zephyrine-wallpaper-desktop
	install -m 755 bin/zephyrine-lock $(DESTDIR)$(BINDIR)/zephyrine-lock
	install -m 755 settings/bin/zs-btagent $(DESTDIR)$(BINDIR)/zs-btagent
	install -m 755 scripts/lock-info.sh $(DESTDIR)$(BINDIR)/lock-info.sh
	install -m 755 scripts/ai-usage-widget.sh $(DESTDIR)$(BINDIR)/ai-usage-widget.sh

	# Внутренние скрипты
	cp -r scripts/* $(DESTDIR)$(LIBDIR)/scripts/
	chmod -R 755 $(DESTDIR)$(LIBDIR)/scripts/

	# Оболочка Quickshell
	cp -r quickshell/* $(DESTDIR)$(DATADIR)/quickshell/

	# Модули Центра Настроек
	cp -r settings/* $(DESTDIR)$(DATADIR)/settings/

	# Конфигурация Hyprland по умолчанию
	cp -r hypr/* $(DESTDIR)$(DATADIR)/hypr/

	# Темы приложений
	cp -r themes/* $(DESTDIR)$(DATADIR)/themes/

	# Ассеты и обои
	cp -r assets/* $(DESTDIR)$(DATADIR)/assets/

	# Сессионные и десктоп файлы
	install -m 644 desktop/zephyrine.desktop $(DESTDIR)$(SESSIONSDIR)/zephyrine.desktop
	install -m 644 desktop/zephyrine-settings.desktop $(DESTDIR)$(APPLICATIONSDIR)/zephyrine-settings.desktop

	# Тема SDDM
	if [ -d sddm/zephyrine ]; then \
		cp -r sddm/zephyrine/* $(DESTDIR)$(SDDMTHEMESDIR)/zephyrine/; \
	fi

	@echo "==> Установка успешно завершена!"

uninstall:
	@echo "==> Удаление Zephyrine Shell..."
	rm -f $(DESTDIR)$(BINDIR)/zephyrine-session
	rm -f $(DESTDIR)$(BINDIR)/zephyrine-settings
	rm -f $(DESTDIR)$(BINDIR)/zephyrine-wallpaper-desktop
	rm -f $(DESTDIR)$(BINDIR)/zephyrine-lock
	rm -f $(DESTDIR)$(BINDIR)/zs-btagent
	rm -f $(DESTDIR)$(BINDIR)/lock-info.sh
	rm -f $(DESTDIR)$(BINDIR)/ai-usage-widget.sh
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -rf $(DESTDIR)$(DATADIR)
	rm -f $(DESTDIR)$(SESSIONSDIR)/zephyrine.desktop
	rm -f $(DESTDIR)$(APPLICATIONSDIR)/zephyrine-settings.desktop
	rm -rf $(DESTDIR)$(SDDMTHEMESDIR)/zephyrine
	@echo "==> Zephyrine Shell удалён."

user-install:
	$(MAKE) PREFIX=$(HOME)/.local install

user-uninstall:
	@echo "==> Удаление Zephyrine Shell из $(HOME)/.local..."
	$(MAKE) PREFIX=$(HOME)/.local uninstall
	@if [ -L $(HOME)/.config/quickshell/zephyrine ]; then \
		rm -f $(HOME)/.config/quickshell/zephyrine; \
		echo "  Удалён симлинк ~/.config/quickshell/zephyrine"; \
	fi

test:
	@echo "==> Запуск тестов модуля zsettings..."
	python3 -m unittest discover -s settings/tests
