class WidgetCiscoSGOverview extends CWidget {

    onInitialize() {
        super.onInitialize();
        this._selected_hostid = null;
        this._payload = null;
        this._modal = null;
        this._sidebar_collapsed = false;
        this._rotationTimer = null;
    }

    setContents(response) {
        super.setContents(response);
        this._renderWidget();
    }

    onResize() {
        super.onResize();
    }

    onClearContents() {
        this._stopHostRotation();
        this._closeModal();
        super.onClearContents();
    }

    _renderWidget() {
        const root = this._body.querySelector('.cisco-switch-root');
        if (!root) return;

        try {
            this._payload = JSON.parse(decodeURIComponent(escape(atob(root.dataset.payload))));
        } catch (e) {
            root.innerHTML = '<div style="padding:20px;text-align:center;">Error al decodificar datos. Verifica la conexión con Zabbix.</div>';
            return;
        }

        const hosts = this._payload.hosts || [];
        if (!hosts.length) {
            root.innerHTML = '<div style="padding:20px;text-align:center;">Por favor, selecciona al menos un switch Cisco en la configuración del widget.</div>';
            return;
        }

        if (!this._selected_hostid || !hosts.some(h => h.hostid === this._selected_hostid)) {
            this._selected_hostid = hosts[0].hostid;
        }

        const currentHost = hosts.find(h => h.hostid === this._selected_hostid);
        const switchData = this._parseSwitchData(currentHost);
        const isCollapsed = this._sidebar_collapsed ? 'is-sidebar-collapsed' : '';

        root.innerHTML = `
            <div class="cs-shell ${isCollapsed}">
                <!-- Menú lateral multiequipo -->
                <aside class="cs-sidebar">
                    <div class="cs-sidebar-header">
                        <strong>Switches SG200</strong>
                        <button class="cs-sidebar-toggle" title="Contraer/Expandir menú">≡</button>
                    </div>
                    <input type="search" class="cs-search" placeholder="Buscar switch...">
                    <div class="cs-host-list">
                        ${hosts.map(h => this._renderHostButton(h)).join('')}
                    </div>
                </aside>
                
                <!-- Área principal de contenido -->
                <main class="cs-main">
                    <header class="cs-header">
                        <div class="cs-header-info">
                            <h2>${this._escape(currentHost.name)}</h2>
                            <p>Uptime: ${switchData.uptime} | IP: ${switchData.ip} | Puertos UP: ${switchData.upCount}/${switchData.ports.length}</p>
                        </div>
                    </header>
                    
                    <div class="cs-content">
                        <!-- KPIs en área principal -->
                        <div class="cs-kpis">
                            <div class="cs-kpi"><span>CPU (1 min)</span><strong>${switchData.cpu !== null ? switchData.cpu + '%' : 'N/D'}</strong></div>
                            <div class="cs-kpi"><span>Tráfico IN</span><strong>${this._formatBits(switchData.totalIn)}</strong></div>
                            <div class="cs-kpi"><span>Tráfico OUT</span><strong>${this._formatBits(switchData.totalOut)}</strong></div>
                        </div>

                        <!-- Faceplate autoajustable -->
                        <div class="cs-faceplate-container">
                            <div class="cs-faceplate">
                                <div class="cs-brand">
                                    <strong>CISCO</strong>
                                    <small>Switch Series</small>
                                </div>
                                <div class="cs-matrix-24">
                                    ${this._render24PortMatrix(switchData.ports)}
                                </div>
                                <div class="cs-uplink-block">
                                    ${this._renderSfpBlock(switchData.ports)}
                                </div>
                            </div>
                        </div>

                        <!-- Tabla sin scroll propio -->
                        <div class="cs-table-wrap">
                            <table class="cs-table">
                                <thead>
                                    <tr>
                                        <th>Puerto</th>
                                        <th>Estado</th>
                                        <th>Tráfico Entrada</th>
                                        <th>Tráfico Salida</th>
                                        <th>Acción</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    ${switchData.ports.map(p => `
                                        <tr data-port-id="${p.index}">
                                            <td><strong>${this._escape(p.name)}</strong></td>
                                            <td><span style="color:${p.status === 1 ? 'var(--cs-green)' : 'var(--cs-muted)'};font-weight:700;">${p.status === 1 ? 'UP' : 'DOWN'}</span></td>
                                            <td>${this._formatBits(p.inTraffic)}</td>
                                            <td>${this._formatBits(p.outTraffic)}</td>
                                            <td><button style="background:var(--cs-panel-soft);border:1px solid var(--cs-border);color:var(--cs-text);padding:3px 8px;border-radius:4px;cursor:pointer;">Ver Gráfica</button></td>
                                        </tr>
                                    `).join('')}
                                </tbody>
                            </table>
                        </div>
                    </div>
                </main>
            </div>
        `;

        // Eventos del Sidebar
        root.querySelectorAll('.cs-host').forEach(btn => {
            btn.addEventListener('click', () => {
                this._selected_hostid = btn.dataset.hostid;
                this._renderWidget();
                this._restartHostRotation();
            });
        });

        root.querySelector('.cs-sidebar-toggle').addEventListener('click', () => {
            this._sidebar_collapsed = !this._sidebar_collapsed;
            this._renderWidget();
        });

        root.querySelector('.cs-search').addEventListener('input', (e) => {
            const term = e.target.value.toLowerCase();
            root.querySelectorAll('.cs-host').forEach(btn => {
                const name = btn.querySelector('strong').textContent.toLowerCase();
                btn.style.display = name.includes(term) ? 'flex' : 'none';
            });
        });

        // Eventos del contenido (Gráficas)
        root.querySelectorAll('[data-chart-in]').forEach(el => {
            el.addEventListener('click', () => {
                this._openChartModal(el.dataset.portName, el.dataset.chartIn, el.dataset.chartOut);
            });
        });

        root.querySelectorAll('.cs-table tbody tr').forEach(row => {
            row.addEventListener('click', () => {
                const p = switchData.ports.find(x => x.index == row.dataset.portId);
                if (p) this._openChartModal(p.name, p.inItemId, p.outItemId);
            });
        });

        this._restartHostRotation();
    }

    _renderHostButton(host) {
        const isActive = host.hostid === this._selected_hostid ? 'is-active' : '';
        const problems = host.problems || [];
        const maxSeverity = problems.reduce((max, p) => Math.max(max, p.severity), -1);
        
        let dotClass = 'ok';
        if (!host.enabled) dotClass = 'nodata';
        else if (maxSeverity >= 4) dotClass = 'crit';
        else if (maxSeverity >= 2) dotClass = 'warn';

        const mainIf = (host.interfaces_meta || []).find(i => String(i.main) === '1') || (host.interfaces_meta || [])[0];
        const ip = mainIf ? (mainIf.ip || mainIf.dns) : 'Sin IP';

        return `
            <button class="cs-host ${isActive}" data-hostid="${this._escape(host.hostid)}" title="${this._escape(host.name)}">
                <span class="cs-dot ${dotClass}"></span>
                <div class="cs-host-info">
                    <strong>${this._escape(host.name)}</strong>
                    <small>${this._escape(ip)}</small>
                </div>
            </button>
        `;
    }

    _parseSwitchData(host) {
        const items = host.items || [];
        let cpu = null, uptimeSec = null, totalIn = 0, totalOut = 0, upCount = 0;
        const portsMap = {};

        items.forEach(item => {
            const key = item.key_;
            if (key === 'rlCpuUtilDuringLastMinute.0' || key.startsWith('system.cpu.util')) {
                cpu = item.lastvalue !== '' ? Math.round(Number(item.lastvalue)) : null;
            }
            if (key === 'sysUpTimeInstance' || key.startsWith('system.uptime')) {
                uptimeSec = item.lastvalue !== '' ? Math.floor(Number(item.lastvalue) / 100) : null;
            }

            const matchIndex = key.match(/\.(\d+)$/);
            if (matchIndex) {
                const idx = parseInt(matchIndex[1], 10);
                if (!portsMap[idx]) {
                    const portNumber = idx >= 49 && idx <= 74 ? idx - 48 : idx;
                    portsMap[idx] = {
                        index: idx, portNumber: portNumber,
                        name: `GE${portNumber < 10 ? '0' + portNumber : portNumber}`,
                        status: 2, inTraffic: 0, outTraffic: 0,
                        inItemId: null, outItemId: null,
                        isSfp: portNumber >= 25
                    };
                }
                if (key.startsWith('ifOperStatus.')) portsMap[idx].status = Number(item.lastvalue) || 2;
                else if (key.startsWith('ifHCInOctets.') || key.startsWith('ifInOctects.') || key.startsWith('ifInOctets.')) {
                    portsMap[idx].inTraffic = Number(item.lastvalue) || 0; portsMap[idx].inItemId = item.itemid;
                } else if (key.startsWith('ifHCOutOctets.') || key.startsWith('ifOutOctets.')) {
                    portsMap[idx].outTraffic = Number(item.lastvalue) || 0; portsMap[idx].outItemId = item.itemid;
                }
            }
        });

        const ports = Object.values(portsMap).sort((a, b) => a.portNumber - b.portNumber);
        ports.forEach(p => {
            if (p.status === 1) upCount++;
            totalIn += p.inTraffic; totalOut += p.outTraffic;
        });
        const mainIf = (host.interfaces_meta || []).find(i => String(i.main) === '1') || (host.interfaces_meta || [])[0];

        return {
            cpu, uptime: this._formatUptime(uptimeSec), ip: mainIf ? (mainIf.ip || mainIf.dns) : 'N/D',
            upCount, totalIn, totalOut, ports
        };
    }

    _render24PortMatrix(ports) {
        let html = '';
        // Fila 1 (arriba): Puertos 1 al 12
        for (let i = 1; i <= 12; i++) {
            html += this._renderPortHtml(ports.find(p => p.portNumber === i));
        }
        // Fila 2 (abajo): Puertos 13 al 24
        for (let i = 13; i <= 24; i++) {
            html += this._renderPortHtml(ports.find(p => p.portNumber === i));
        }
        return html;
    }

    _renderSfpBlock(ports) {
        return [25, 26].map(num => this._renderPortHtml(ports.find(p => p.portNumber === num))).join('');
    }

    _renderPortHtml(p) {
        if (!p) return '<div class="cs-port" style="visibility:hidden;"></div>';
        const hasTraffic = (p.inTraffic + p.outTraffic) > 50000;
        return `
            <div class="cs-port ${p.status === 1 ? 'up' : 'down'} ${hasTraffic ? 'has-traffic' : ''} ${p.isSfp ? 'is-sfp' : ''}"
                 data-chart-in="${p.inItemId || ''}" data-chart-out="${p.outItemId || ''}"
                 data-port-name="${this._escape(p.name)}"
                 title="${p.name} | ${p.status === 1 ? 'UP' : 'DOWN'}&#10;IN: ${this._formatBits(p.inTraffic)}&#10;OUT: ${this._formatBits(p.outTraffic)}">
                <span class="cs-port-num">${p.portNumber}</span>
                <span class="cs-led"></span>
                <div class="cs-jack"></div>
            </div>
        `;
    }

    _restartHostRotation() {
        this._stopHostRotation();
        const hosts = this._payload?.hosts || [];
        const enabled = Number(this._payload?.settings?.enable_auto_rotation) === 1;
        const seconds = Math.max(0, Number(this._payload?.settings?.page_display_period) || 0);

        if (!enabled || hosts.length < 2 || seconds === 0) return;

        this._rotationTimer = window.setInterval(() => {
            if (this._modal) return;
            const current = hosts.findIndex(h => h.hostid === this._selected_hostid);
            this._selected_hostid = hosts[(current + 1) % hosts.length].hostid;
            this._renderWidget();
        }, seconds * 1000);
    }

    _stopHostRotation() {
        if (this._rotationTimer !== null) {
            window.clearInterval(this._rotationTimer);
            this._rotationTimer = null;
        }
    }

    _openChartModal(title, inItemId, outItemId) {
        this._closeModal();
        this._modal = document.createElement('div');
        this._modal.className = 'cs-modal';
        this._modal.innerHTML = `
            <div class="cs-modal-card">
                <div class="cs-modal-header">
                    <h3>Tráfico Histórico: ${this._escape(title)}</h3>
                    <button class="cs-modal-close">&times;</button>
                </div>
                <canvas class="cs-chart"></canvas>
                <div style="display:flex;justify-content:space-between;margin-top:8px;font-size:10px;color:var(--cs-muted);">
                    <span><i style="display:inline-block;width:8px;height:8px;background:#049fd9;border-radius:50%;margin-right:4px;"></i>Entrada (IN)</span>
                    <span><i style="display:inline-block;width:8px;height:8px;background:#2ecc71;border-radius:50%;margin-right:4px;"></i>Salida (OUT)</span>
                </div>
            </div>
        `;
        document.body.appendChild(this._modal);
        this._modal.querySelector('.cs-modal-close').addEventListener('click', () => this._closeModal());
        this._modal.addEventListener('click', (e) => { if (e.target === this._modal) this._closeModal(); });

        const canvas = this._modal.querySelector('canvas.cs-chart');
        this._drawModalChart(canvas, [inItemId, outItemId].filter(Boolean));
    }

    _drawModalChart(canvas, itemids) {
        const ctx = canvas.getContext('2d');
        const rect = canvas.getBoundingClientRect();
        canvas.width = rect.width; canvas.height = rect.height;

        const colors = ['#049fd9', '#2ecc71'];
        const series = itemids.map((id, idx) => ({
            points: (this._payload.history[id] || []), color: colors[idx % colors.length]
        })).filter(s => s.points.length > 0);

        if (!series.length) {
            ctx.fillStyle = '#8c9ba8';
            ctx.fillText('Sin datos históricos en Zabbix para este puerto.', 20, canvas.height / 2);
            return;
        }

        const allVals = series.flatMap(s => s.points.map(p => p[1]));
        const maxVal = Math.max(1000, ...allVals) * 1.1;
        const pad = { t: 20, b: 25, l: 50, r: 20 };
        const w = canvas.width - pad.l - pad.r;
        const h = canvas.height - pad.t - pad.b;

        ctx.strokeStyle = 'rgba(255,255,255,0.1)';
        ctx.beginPath();
        ctx.moveTo(pad.l, pad.t); ctx.lineTo(pad.l, pad.t + h); ctx.lineTo(pad.l + w, pad.t + h);
        ctx.stroke();

        series.forEach(s => {
            const pts = s.points;
            const minT = pts[0][0]; const maxT = pts[pts.length - 1][0];
            const timeSpan = Math.max(1, maxT - minT);

            ctx.beginPath();
            ctx.strokeStyle = s.color;
            ctx.lineWidth = 2;

            pts.forEach((pt, i) => {
                const x = pad.l + ((pt[0] - minT) / timeSpan) * w;
                const y = pad.t + h - (pt[1] / maxVal) * h;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            });
            ctx.stroke();
        });
    }

    _closeModal() {
        if (this._modal) { this._modal.remove(); this._modal = null; }
    }

    _formatBits(val) {
        if (!val || isNaN(val)) return '0 bps';
        const units = ['bps', 'Kbps', 'Mbps', 'Gbps'];
        let i = 0, v = Number(val);
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        return `${v.toFixed(1)} ${units[i]}`;
    }

    _formatUptime(sec) {
        if (!sec || isNaN(sec)) return 'N/D';
        const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60);
        return `${d}d ${h}h ${m}m`;
    }

    _escape(str) {
        return String(str || '').replace(/[&<>'"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[c]));
    }
}
