#!/bin/bash
MODULE_DIR="/usr/share/zabbix/modules/CiscoSGOverview"
# (Copia y pega el contenido del CSS y JS en los archivos correspondientes usando comandos directos o subiéndolos vía SFTP/VSCode)
# Aplicamos permisos
chown -R zabbix:zabbix $MODULE_DIR
chmod -R 755 $MODULE_DIR
