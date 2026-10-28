// The resource view: renders admin_resource_list and admin_resource_show results, and, when the
// host proxies tool calls, pages, sorts, searches and follows associations in place.
(function () {
  'use strict';

  var A = window.AdministrateMCP;
  var h = A.h;
  var HINTS_KEY = 'administrate-mcp/view';
  var LIST_TOOL = 'admin_resource_list';
  var SHOW_TOOL = 'admin_resource_show';
  var IMAGE_PATH = /\.(png|jpe?g|gif|webp|avif|svg)(\?|#|$)/i;
  var ISO_DATE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;

  var stack = [];
  var input = {};

  function current() {
    return stack[stack.length - 1];
  }

  function humanize(name) {
    var text = String(name).replace(/_id$/, '').replace(/[_/]+/g, ' ').trim();
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  function resourceForType(type) {
    return String(type)
      .replace(/::/g, '/')
      .replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')
      .replace(/([a-z\d])([A-Z])/g, '$1_$2')
      .toLowerCase();
  }

  function screenFrom(result, args) {
    var hints = A.resultMeta(result, HINTS_KEY) || {};
    var screen = {
      args: Object.assign({}, args),
      resource: hints.resource || args.resource,
      fields: hints.fields || {},
      error: A.resultError(result)
    };
    if (screen.error) return Object.assign(screen, { kind: 'error' });

    var data = A.resultData(result);
    screen.data = data;
    if (data && data.status === 'ok' && data.action && data.model) {
      screen.kind = 'action';
      screen.resource = data.model;
    } else if (data && Array.isArray(data.columns) && Array.isArray(data.rows)) {
      screen.kind = data.meta && data.meta.page ? 'list' : 'batch';
    } else if (data && typeof data === 'object') {
      screen.kind = 'show';
    } else {
      screen.kind = 'error';
      screen.error = typeof data === 'string' ? data : 'Nothing to show.';
    }
    return screen;
  }

  function describe(screen) {
    if (screen.kind === 'action') return 'the result of ' + screen.data.action + ' on ' + screen.resource;
    if (screen.kind === 'show') return 'the ' + screen.resource + ' record ' + recordLabel(screen);
    if (screen.kind === 'list') {
      var meta = screen.data.meta;
      return 'page ' + meta.page + ' of ' + meta.total_pages + ' of the ' + screen.resource + ' list (' +
        meta.total_count + ' records' + (screen.args.query ? ', search "' + screen.args.query + '"' : '') + ')';
    }
    return 'the ' + screen.resource + ' records';
  }

  function load(tool, args, mode) {
    var previous = current();
    if (previous) previous.loading = true;
    render();
    return A.callTool(tool, args).then(function (result) {
      var screen = screenFrom(result, args);
      if (mode === 'replace') stack[stack.length - 1] = screen;
      else stack.push(screen);
      render();
      A.updateModelContext('The user is viewing ' + describe(screen) + ' in the admin view.');
    }).catch(function (error) {
      if (previous) {
        previous.loading = false;
        previous.notice = error.message;
      }
      render();
    });
  }

  function openShow(resource, id) {
    load(SHOW_TOOL, { resource: resource, id: String(id) }, 'push');
  }

  function openList(resource, filters) {
    load(LIST_TOOL, { resource: resource, filters: filters }, 'push');
  }

  function relist(changes) {
    var args = Object.assign({}, current().args, changes);
    load(LIST_TOOL, args, 'replace');
  }

  function recordLabel(screen) {
    var data = screen.data || {};
    return data.name || data.title || data.display_name || data.label || data.email || data.slug ||
      (data.id !== undefined ? '#' + data.id : '');
  }

  function empty() {
    return h('span', { className: 'am-muted' }, '—');
  }

  function json(value, compact) {
    var size = Array.isArray(value) ? value.length + ' items' : Object.keys(value).length + ' keys';
    if (compact) return h('span', { className: 'am-muted' }, size);
    return h('details', { className: 'am-json' }, h('summary', null, size), h('pre', null, JSON.stringify(value, null, 2)));
  }

  function attachment(url, compact) {
    if (!A.isSafeUrl(url)) return document.createTextNode(String(url));
    if (!IMAGE_PATH.test(url)) return A.link(url, compact ? 'File' : url);
    var image = h('img', { src: url, alt: '', className: compact ? 'am-thumb' : 'am-image', loading: 'lazy' });
    image.addEventListener('error', function () {
      image.replaceWith(A.link(url, compact ? 'Image' : url));
    });
    return h('a', {
      href: url,
      onClick: function (event) {
        event.preventDefault();
        A.openLink(url);
      }
    }, image);
  }

  function related(value, hint) {
    var label = value.display || value.slug || '#' + value.id;
    var resource = (hint && hint.resource) || (value.type && resourceForType(value.type));
    if (!resource || !A.canCallTools()) return document.createTextNode(label);
    return h('button', {
      className: 'am-link',
      title: 'Open ' + resource + ' ' + value.id,
      onClick: function (event) {
        event.stopPropagation();
        openShow(resource, value.id);
      }
    }, label);
  }

  function hasMany(value, hint, name, owner, compact) {
    var count = value.count;
    var label = count + ' ' + humanize(name).toLowerCase();
    var canFollow = hint && hint.resource && hint.foreign_key && owner && owner.id !== undefined && A.canCallTools();
    var summary = canFollow && count > 0
      ? h('button', {
        className: 'am-link',
        onClick: function (event) {
          event.stopPropagation();
          var filters = {};
          filters[hint.foreign_key] = owner.id;
          openList(hint.resource, filters);
        }
      }, label)
      : h('span', null, label);
    if (compact || !Array.isArray(value.items) || value.items.length === 0) return summary;

    var columns = Object.keys(value.items[0]).filter(function (key) { return key !== 'url'; });
    var rows = value.items.map(function (item) { return columns.map(function (key) { return item[key]; }); });
    var shown = value.items.length < count ? h('p', { className: 'am-muted' }, 'Showing ' + value.items.length + ' of ' + count + '.') : null;
    return h('div', null, summary, table(columns, rows, {}, {
      resource: hint && hint.resource,
      urls: value.items.map(function (item) { return item.url; })
    }), shown);
  }

  function isRelated(value) {
    return Object.keys(value).every(function (key) { return ['id', 'display', 'slug', 'type'].indexOf(key) >= 0; });
  }

  function renderValue(value, hint, name, owner, compact) {
    var kind = hint && hint.kind;
    if (value === null || value === undefined || value === '') return empty();
    if (typeof value === 'boolean') return h('span', { className: 'am-badge am-' + value }, value ? 'Yes' : 'No');
    if (typeof value === 'number') return document.createTextNode(value.toLocaleString());
    if (typeof value === 'object' && !Array.isArray(value)) {
      if (kind === 'has_many' || (value.count !== undefined && Object.keys(value).every(function (key) { return key === 'count' || key === 'items'; }))) {
        return hasMany(value, hint, name, owner, compact);
      }
      if (value.id !== undefined && (kind === 'belongs_to' || kind === 'polymorphic' || isRelated(value))) {
        return related(value, hint);
      }
      return json(value, compact);
    }
    if (Array.isArray(value)) return json(value, compact);
    if (typeof value === 'string' && kind === 'attachment') return attachment(value, compact);
    if (typeof value === 'string' && (kind === 'datetime' || ISO_DATE.test(value))) {
      return h('time', { datetime: value, title: value }, A.formatDate(value));
    }
    if (kind === 'enum') return h('span', { className: 'am-badge' }, String(value));
    if (typeof value === 'string' && A.isSafeUrl(value)) return A.link(value, value);
    return document.createTextNode(String(value));
  }

  function table(columns, rows, fields, options) {
    var idIndex = columns.indexOf('id');
    var sort = options.sort;
    var head = h('tr', null, columns.map(function (column) {
      var label = humanize(column);
      if (!options.onSort) return h('th', { scope: 'col' }, label);
      var arrow = sort && sort.field === column ? (sort.direction === 'asc' ? ' ▲' : ' ▼') : '';
      return h('th', { scope: 'col' }, h('button', {
        className: 'am-link',
        title: 'Sort by ' + label,
        onClick: function () { options.onSort(column); }
      }, label + arrow));
    }));

    var body = rows.map(function (row, index) {
      if (!Array.isArray(row)) {
        return h('tr', null, h('td', { colspan: columns.length, className: 'am-error' }, (row && row.error) || 'Not found'));
      }
      var owner = idIndex >= 0 ? { id: row[idIndex] } : null;
      var url = options.urls && options.urls[index];
      var target = options.resource && owner && A.canCallTools()
        ? function () { openShow(options.resource, owner.id); }
        : (A.isSafeUrl(url) ? function () { A.openLink(url); } : null);
      return h('tr', { className: target ? 'am-clickable' : null, onClick: target },
        row.map(function (value, column) {
          return h('td', null, renderValue(value, fields[columns[column]], columns[column], owner, true));
        }));
    });

    return h('div', { className: 'am-table-wrap' },
      h('table', { className: 'am-table' }, h('thead', null, head), h('tbody', null, body)));
  }

  function backButton() {
    if (stack.length < 2) return null;
    return h('button', {
      title: 'Back',
      onClick: function () {
        stack.pop();
        render();
        A.updateModelContext('The user is viewing ' + describe(current()) + ' in the admin view.');
      }
    }, '←');
  }

  function toolbar(screen, title, extra, kicker) {
    return h('div', { className: 'am-toolbar' },
      backButton(),
      kicker ? h('span', { className: 'am-badge' }, kicker) : null,
      h('h1', null, title),
      extra,
      screen.loading ? h('span', { className: 'am-muted' }, 'Loading…') : null);
  }

  function splitRows(data) {
    var urlIndex = data.columns.indexOf('url');
    var columns = data.columns.filter(function (_, index) { return index !== urlIndex; });
    var urls = [];
    var rows = data.rows.map(function (row) {
      if (!Array.isArray(row)) return row;
      urls.push(urlIndex >= 0 ? row[urlIndex] : null);
      return row.filter(function (_, index) { return index !== urlIndex; });
    });
    return { columns: columns, rows: rows, urls: urls };
  }

  function renderList(screen) {
    var data = screen.data;
    var meta = data.meta || {};
    var split = splitRows(data);
    var interactive = screen.kind === 'list' && A.canCallTools();
    var sort = screen.args.sort ? { field: screen.args.sort, direction: screen.args.sort_direction || 'desc' } : null;

    var search = interactive ? h('form', {
      onSubmit: function (event) {
        event.preventDefault();
        relist({ query: event.target.elements.query.value || undefined, page: 1 });
      }
    }, h('input', { type: 'search', name: 'query', placeholder: 'Search', value: screen.args.query || '' })) : null;

    var count = screen.kind === 'list'
      ? h('span', { className: 'am-muted' }, meta.total_count + ' record' + (meta.total_count === 1 ? '' : 's'))
      : null;

    var pager = screen.kind === 'list' && meta.total_pages > 1 ? h('div', { className: 'am-toolbar am-pager' },
      h('button', { disabled: !interactive || meta.page <= 1, onClick: function () { relist({ page: meta.page - 1 }); } }, 'Previous'),
      h('span', { className: 'am-muted' }, 'Page ' + meta.page + ' of ' + meta.total_pages),
      h('button', { disabled: !interactive || meta.page >= meta.total_pages, onClick: function () { relist({ page: meta.page + 1 }); } }, 'Next')
    ) : null;

    var body = split.rows.length === 0
      ? A.message('No records match.')
      : table(split.columns, split.rows, screen.fields, {
        resource: screen.resource,
        urls: split.urls,
        sort: sort,
        onSort: interactive ? function (field) {
          var direction = sort && sort.field === field && sort.direction === 'desc' ? 'asc' : 'desc';
          relist({ sort: field, sort_direction: direction, page: 1 });
        } : null
      });

    return h('div', null, toolbar(screen, humanize(screen.resource || 'Records'), [count, h('span', { className: 'am-spacer' }), search]), body, pager);
  }

  function renderShow(screen) {
    var data = screen.data;
    var open = A.isSafeUrl(data.url) ? h('button', { onClick: function () { A.openLink(data.url); } }, 'Open in admin') : null;
    var keys = Object.keys(data).filter(function (key) { return key !== 'url'; });
    var fields = h('dl', { className: 'am-fields' }, keys.map(function (key) {
      return [
        h('dt', null, humanize(key)),
        h('dd', null, renderValue(data[key], screen.fields[key], key, data, false))
      ];
    }));
    var resource = humanize(screen.resource || 'Record');
    return h('div', null, toolbar(screen, recordLabel(screen) || resource, [h('span', { className: 'am-spacer' }), open], resource), fields);
  }

  function loadActionRecord(screen) {
    screen.recordRequested = true;
    A.callTool(SHOW_TOOL, { resource: screen.resource, id: String(screen.data.id) }).then(function (result) {
      screen.record = screenFrom(result, { resource: screen.resource, id: String(screen.data.id) });
      render();
    }).catch(function () {
      screen.record = null;
    });
  }

  function renderAction(screen) {
    var data = screen.data;
    var extra = data.data && typeof data.data === 'object' && Object.keys(data.data).length
      ? h('div', { className: 'am-action-data' }, h('h2', null, 'Returned data'), json(data.data, false))
      : null;
    var title = humanize(data.action) + ' — done';
    var view = h('div', null, toolbar(screen, title, [h('span', { className: 'am-spacer' }), h('span', { className: 'am-badge am-true' }, 'OK')], humanize(screen.resource)), extra);
    if (data.id !== undefined && A.canCallTools() && !screen.recordRequested) loadActionRecord(screen);
    if (screen.record && screen.record.kind === 'show') {
      var record = renderShow(screen.record);
      record.classList.add('am-action-record');
      view.appendChild(record);
    } else if (data.id !== undefined && !A.canCallTools()) {
      view.appendChild(A.message(humanize(screen.resource) + ' ' + data.id));
    }
    return view;
  }

  function render() {
    var screen = current();
    if (!screen) return;
    var view;
    if (screen.kind === 'action') {
      view = renderAction(screen);
    } else if (screen.kind === 'error') {
      view = h('div', null, toolbar(screen, humanize(screen.resource || A.toolName() || 'Admin'), null), A.message(screen.error, 'am-error'));
    } else if (screen.kind === 'show') {
      view = renderShow(screen);
    } else {
      view = renderList(screen);
    }
    if (screen.notice) view.appendChild(A.message(screen.notice, 'am-error'));
    screen.notice = null;
    A.mount(view);
  }

  A.on('input', function (args) {
    input = args || {};
  });

  A.on('result', function (result) {
    stack = [screenFrom(result, input)];
    render();
  });

  A.on('cancelled', function () {
    if (!stack.length) A.mount(A.message('The tool call was cancelled.'));
  });

  A.connect().catch(function (error) {
    A.mount(A.message('Could not connect to the host: ' + error.message, 'am-error'));
  });
})();
