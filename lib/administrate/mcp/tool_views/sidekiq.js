// The Sidekiq view: renders sidekiq_stats as counts per job class and sidekiq_retries as the
// retry queue, and re-runs the call in place when the host proxies tool calls.
(function () {
  'use strict';

  var A = window.AdministrateMCP;
  var h = A.h;
  var input = {};
  var screen = null;

  function toolFor(data) {
    return A.toolName() || (data && data.total_size !== undefined ? 'sidekiq_retries' : 'sidekiq_stats');
  }

  function rerun(changes) {
    var args = Object.assign({}, screen.args, changes);
    screen.loading = true;
    render();
    A.callTool(screen.tool, args).then(function (result) {
      show(result, args);
    }).catch(function (error) {
      screen.loading = false;
      screen.notice = error.message;
      render();
    });
  }

  function show(result, args) {
    var data = A.resultData(result);
    screen = { args: args || {}, data: data, error: A.resultError(result), tool: toolFor(data) };
    render();
  }

  function bars(counts) {
    var entries = Object.keys(counts || {}).map(function (name) { return [name, counts[name]]; });
    if (entries.length === 0) return A.message('Nothing queued.');
    var max = Math.max.apply(null, entries.map(function (entry) { return entry[1]; })) || 1;
    return h('div', { className: 'am-bars' }, entries.map(function (entry) {
      return h('div', { className: 'am-bar-row' },
        h('span', { className: 'am-bar-label am-mono', title: entry[0] }, entry[0]),
        h('span', { className: 'am-bar-track' }, h('span', { className: 'am-bar', style: 'width:' + Math.max(2, (entry[1] / max) * 100) + '%' })),
        h('span', { className: 'am-bar-value' }, entry[1].toLocaleString()));
    }));
  }

  function retriesTable(entries) {
    if (!entries.length) return A.message('The retry queue is empty.');
    var head = ['Job', 'Error', 'Retries', 'Failed', 'Next retry'];
    return h('div', { className: 'am-table-wrap' }, h('table', { className: 'am-table' },
      h('thead', null, h('tr', null, head.map(function (label) { return h('th', { scope: 'col' }, label); }))),
      h('tbody', null, entries.map(function (entry) {
        return h('tr', null,
          h('td', null, h('div', { className: 'am-mono' }, entry.class), h('div', { className: 'am-muted' }, entry.queue)),
          h('td', null, h('div', null, entry.error_class), h('div', { className: 'am-muted' }, entry.error_message)),
          h('td', null, String(entry.retry_count === undefined ? '' : entry.retry_count)),
          h('td', null, entry.failed_at ? A.formatDate(entry.failed_at) : ''),
          h('td', null, entry.next_retry_at ? A.formatDate(entry.next_retry_at) : ''));
      }))));
  }

  function statsView(data) {
    var parts = [
      h('h2', null, 'Retries by job class ', h('span', { className: 'am-muted' }, '(' + (data.total_retries || 0).toLocaleString() + ')')),
      bars(data.retries)
    ];
    if (data.queues) {
      Object.keys(data.queues).forEach(function (queue) {
        var entry = data.queues[queue];
        parts.push(h('h2', null, queue + ' ', h('span', { className: 'am-muted' }, '(' + (entry.total || 0).toLocaleString() + ')')));
        parts.push(bars(entry.counts));
      });
    } else if (A.canCallTools()) {
      parts.push(h('button', { onClick: function () { rerun({ include_queues: true }); } }, 'Show queues'));
    }
    if (data.stats_cleared_at) parts.push(A.message('Counting since ' + A.formatDate(data.stats_cleared_at) + '.'));
    return parts;
  }

  function retriesView(data) {
    var parts = [h('p', null, h('strong', null, (data.total_size || 0).toLocaleString()), ' jobs waiting to retry.')];
    if (data.entries) parts.push(retriesTable(data.entries));
    else if (A.canCallTools()) parts.push(h('button', { onClick: function () { rerun({ include_entries: true }); } }, 'Show the first jobs'));
    return parts;
  }

  function render() {
    if (!screen) return;
    var data = screen.data || {};
    var refresh = A.canCallTools() ? h('button', { onClick: function () { rerun({}); }, disabled: screen.loading }, 'Refresh') : null;
    var title = screen.tool === 'sidekiq_retries' ? 'Sidekiq retries' : 'Sidekiq stats';
    var body = screen.error
      ? A.message(screen.error, 'am-error')
      : (screen.tool === 'sidekiq_retries' ? retriesView(data) : statsView(data));
    var view = h('div', null,
      h('div', { className: 'am-toolbar' }, h('h1', null, title), h('span', { className: 'am-spacer' }),
        screen.loading ? h('span', { className: 'am-muted' }, 'Loading…') : null, refresh),
      body,
      screen.notice ? A.message(screen.notice, 'am-error') : null);
    screen.notice = null;
    A.mount(view);
  }

  A.on('input', function (args) { input = args || {}; });
  A.on('result', function (result) { show(result, input); });
  A.connect().catch(function (error) {
    A.mount(A.message('Could not connect to the host: ' + error.message, 'am-error'));
  });
})();
