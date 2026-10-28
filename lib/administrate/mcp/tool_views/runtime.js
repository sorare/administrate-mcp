// The runtime every administrate-mcp tool view shares: the MCP Apps (SEP-1865) postMessage
// bridge to the host, theming from the host context, automatic resizing, and DOM helpers that
// only ever set text, never markup, because what they render is admin data.
(function () {
  'use strict';

  var PROTOCOL_VERSION = '2026-01-26';
  var URL_ATTRIBUTES = ['href', 'src', 'srcset', 'action', 'formaction', 'xlink:href', 'poster'];
  var nextId = 1;
  var pending = {};
  var listeners = {};
  var state = { hostContext: {}, hostCapabilities: {}, toolInput: null, toolResult: null };

  function post(message) {
    window.parent.postMessage(Object.assign({ jsonrpc: '2.0' }, message), '*');
  }

  function request(method, params) {
    var id = nextId++;
    return new Promise(function (resolve, reject) {
      pending[id] = { resolve: resolve, reject: reject };
      post({ id: id, method: method, params: params || {} });
    });
  }

  function notify(method, params) {
    post({ method: method, params: params || {} });
  }

  function emit(event, payload) {
    (listeners[event] || []).forEach(function (callback) {
      try {
        callback(payload);
      } catch (error) {
        console.error(error);
      }
    });
  }

  function on(event, callback) {
    (listeners[event] = listeners[event] || []).push(callback);
    if (event === 'input' && state.toolInput) callback(state.toolInput);
    if (event === 'result' && state.toolResult) callback(state.toolResult);
  }

  function respond(id, result) {
    post({ id: id, result: result || {} });
  }

  function handleRequest(message) {
    if (message.method === 'ui/resource-teardown') {
      emit('teardown', message.params);
      respond(message.id);
    } else if (message.method === 'ping') {
      respond(message.id);
    } else {
      post({ id: message.id, error: { code: -32601, message: 'Method not found' } });
    }
  }

  function handleNotification(message) {
    var params = message.params || {};
    switch (message.method) {
      case 'ui/notifications/tool-input':
        state.toolInput = params.arguments || {};
        emit('input', state.toolInput);
        break;
      case 'ui/notifications/tool-result':
        state.toolResult = params;
        emit('result', params);
        break;
      case 'ui/notifications/tool-cancelled':
        emit('cancelled', params);
        break;
      case 'ui/notifications/host-context-changed':
        applyHostContext(Object.assign(state.hostContext, params));
        break;
      default:
        break;
    }
  }

  window.addEventListener('message', function (event) {
    if (event.source !== window.parent) return;
    var message = event.data;
    if (!message || message.jsonrpc !== '2.0') return;

    if (message.id !== undefined && !message.method) {
      var waiter = pending[message.id];
      if (!waiter) return;
      delete pending[message.id];
      if (message.error) waiter.reject(new Error(message.error.message || 'Request failed'));
      else waiter.resolve(message.result);
    } else if (message.id !== undefined) {
      handleRequest(message);
    } else if (message.method) {
      handleNotification(message);
    }
  });

  function applyHostContext(context) {
    var root = document.documentElement;
    if (context.theme) root.dataset.theme = context.theme;
    var variables = context.styles && context.styles.variables;
    if (variables) {
      Object.keys(variables).forEach(function (name) {
        if (variables[name]) root.style.setProperty(name, variables[name]);
      });
    }
    var dimensions = context.containerDimensions;
    if (dimensions && dimensions.maxHeight) root.style.maxHeight = dimensions.maxHeight + 'px';
    emit('context', context);
  }

  function watchSize() {
    var last = '';
    var report = function () {
      var box = document.body.getBoundingClientRect();
      var width = Math.ceil(Math.max(box.width, document.body.scrollWidth));
      var height = Math.ceil(box.height);
      var key = width + 'x' + height;
      if (key === last) return;
      last = key;
      notify('ui/notifications/size-changed', { width: width, height: height });
    };
    if (window.ResizeObserver) new ResizeObserver(report).observe(document.body);
    report();
  }

  function connect() {
    var app = { name: 'administrate-mcp', version: '1' };
    return request('ui/initialize', {
      protocolVersion: PROTOCOL_VERSION,
      appInfo: app,
      clientInfo: app,
      capabilities: {},
      appCapabilities: { availableDisplayModes: ['inline', 'fullscreen'] }
    }).then(function (result) {
      state.hostCapabilities = (result && result.hostCapabilities) || {};
      state.hostContext = (result && result.hostContext) || {};
      applyHostContext(state.hostContext);
      notify('ui/notifications/initialized');
      watchSize();
      return result;
    });
  }

  function resultData(result) {
    if (!result) return null;
    if (result.structuredContent) return result.structuredContent;
    var texts = (result.content || []).filter(function (block) { return block.type === 'text'; });
    for (var i = texts.length - 1; i >= 0; i--) {
      try {
        return JSON.parse(texts[i].text);
      } catch (_error) {
        continue;
      }
    }
    return texts.length ? texts[0].text : null;
  }

  function resultError(result) {
    if (!result || !result.isError) return null;
    var text = (result.content || []).find(function (block) { return block.type === 'text'; });
    return text ? text.text : 'The tool call failed.';
  }

  function resultMeta(result, key) {
    return (result && result._meta && result._meta[key]) || null;
  }

  function toolName() {
    var info = state.hostContext.toolInfo;
    return (info && info.tool && info.tool.name) || null;
  }

  function canCallTools() {
    return Boolean(state.hostCapabilities.serverTools);
  }

  function callTool(name, args) {
    return request('tools/call', { name: name, arguments: args || {} });
  }

  function openLink(url) {
    if (!isSafeUrl(url)) return Promise.reject(new Error('Only http and https links can be opened.'));
    return request('ui/open-link', { url: url }).catch(function () {
      window.open(url, '_blank', 'noopener');
    });
  }

  function sendMessage(text) {
    return request('ui/message', { role: 'user', content: { type: 'text', text: text } });
  }

  function updateModelContext(text) {
    return request('ui/update-model-context', { content: [{ type: 'text', text: text }] }).catch(function () {});
  }

  function requestDisplayMode(mode) {
    return request('ui/request-display-mode', { mode: mode });
  }

  function h(tag, attributes) {
    var element = document.createElement(tag);
    var attrs = attributes || {};
    Object.keys(attrs).forEach(function (key) {
      var value = attrs[key];
      if (value === null || value === undefined || value === false) return;
      if (key.indexOf('on') === 0) {
        if (typeof value === 'function') element.addEventListener(key.slice(2).toLowerCase(), value);
      } else if (URL_ATTRIBUTES.indexOf(key.toLowerCase()) >= 0 && !isSafeUrl(value)) {
        return;
      } else if (key === 'className') {
        element.className = value;
      } else if (key === 'dataset') {
        Object.assign(element.dataset, value);
      } else {
        element.setAttribute(key, value === true ? '' : String(value));
      }
    });
    for (var i = 2; i < arguments.length; i++) append(element, arguments[i]);
    return element;
  }

  function append(parent, child) {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) {
      child.forEach(function (item) { append(parent, item); });
    } else if (child instanceof Node) {
      parent.appendChild(child);
    } else {
      parent.appendChild(document.createTextNode(String(child)));
    }
  }

  function mount(node) {
    var root = document.getElementById('app');
    root.replaceChildren(node);
  }

  function isSafeUrl(value) {
    return typeof value === 'string' && /^https?:\/\//i.test(value);
  }

  function link(url, label) {
    if (!isSafeUrl(url)) return document.createTextNode(label || '');
    return h('a', {
      href: url,
      onClick: function (event) {
        event.preventDefault();
        openLink(url);
      }
    }, label || url);
  }

  function formatDate(value) {
    var date = new Date(value);
    if (isNaN(date.getTime())) return String(value);
    try {
      return date.toLocaleString(state.hostContext.locale || undefined, {
        dateStyle: 'medium',
        timeStyle: 'short',
        timeZone: state.hostContext.timeZone || undefined
      });
    } catch (_error) {
      return date.toLocaleString();
    }
  }

  function message(text, className) {
    return h('p', { className: className || 'am-muted' }, text);
  }

  window.AdministrateMCP = {
    state: state,
    connect: connect,
    on: on,
    callTool: callTool,
    canCallTools: canCallTools,
    toolName: toolName,
    openLink: openLink,
    sendMessage: sendMessage,
    updateModelContext: updateModelContext,
    requestDisplayMode: requestDisplayMode,
    resultData: resultData,
    resultError: resultError,
    resultMeta: resultMeta,
    h: h,
    mount: mount,
    link: link,
    isSafeUrl: isSafeUrl,
    formatDate: formatDate,
    message: message
  };
})();
