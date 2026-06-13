#!/usr/bin/env bun
// @bun
var __defProp = Object.defineProperty;
var __returnValue = (v) => v;
function __exportSetter(name, newValue) {
  this[name] = __returnValue.bind(null, newValue);
}
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, {
      get: all[name],
      enumerable: true,
      configurable: true,
      set: __exportSetter.bind(all, name)
    });
};

// src/index.ts
import { mkdirSync } from "fs";
import { dirname } from "path";

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Pipeable.js
var pipeArguments = (self, args) => {
  switch (args.length) {
    case 0:
      return self;
    case 1:
      return args[0](self);
    case 2:
      return args[1](args[0](self));
    case 3:
      return args[2](args[1](args[0](self)));
    case 4:
      return args[3](args[2](args[1](args[0](self))));
    case 5:
      return args[4](args[3](args[2](args[1](args[0](self)))));
    case 6:
      return args[5](args[4](args[3](args[2](args[1](args[0](self))))));
    case 7:
      return args[6](args[5](args[4](args[3](args[2](args[1](args[0](self)))))));
    case 8:
      return args[7](args[6](args[5](args[4](args[3](args[2](args[1](args[0](self))))))));
    case 9:
      return args[8](args[7](args[6](args[5](args[4](args[3](args[2](args[1](args[0](self)))))))));
    default: {
      let ret = self;
      for (let i = 0, len = args.length;i < len; i++) {
        ret = args[i](ret);
      }
      return ret;
    }
  }
};
var Prototype = {
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var Class = /* @__PURE__ */ function() {
  function PipeableBase() {}
  PipeableBase.prototype = Prototype;
  return PipeableBase;
}();

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Function.js
var dual = function(arity, body) {
  if (typeof arity === "function") {
    return function() {
      return arity(arguments) ? body.apply(this, arguments) : (self) => body(self, ...arguments);
    };
  }
  switch (arity) {
    case 0:
    case 1:
      throw new RangeError(`Invalid arity ${arity}`);
    case 2:
      return function(a, b) {
        if (arguments.length >= 2) {
          return body(a, b);
        }
        return function(self) {
          return body(self, a);
        };
      };
    case 3:
      return function(a, b, c) {
        if (arguments.length >= 3) {
          return body(a, b, c);
        }
        return function(self) {
          return body(self, a, b);
        };
      };
    default:
      return function() {
        if (arguments.length >= arity) {
          return body.apply(this, arguments);
        }
        const args = arguments;
        return function(self) {
          return body(self, ...args);
        };
      };
  }
};
var identity = (a) => a;
var constant = (value) => () => value;
var constTrue = /* @__PURE__ */ constant(true);
var constFalse = /* @__PURE__ */ constant(false);
var constUndefined = /* @__PURE__ */ constant(undefined);
var constVoid = constUndefined;
function flow(ab, bc, cd, de, ef, fg, gh, hi, ij) {
  switch (arguments.length) {
    case 1:
      return ab;
    case 2:
      return function() {
        return bc(ab.apply(this, arguments));
      };
    case 3:
      return function() {
        return cd(bc(ab.apply(this, arguments)));
      };
    case 4:
      return function() {
        return de(cd(bc(ab.apply(this, arguments))));
      };
    case 5:
      return function() {
        return ef(de(cd(bc(ab.apply(this, arguments)))));
      };
    case 6:
      return function() {
        return fg(ef(de(cd(bc(ab.apply(this, arguments))))));
      };
    case 7:
      return function() {
        return gh(fg(ef(de(cd(bc(ab.apply(this, arguments)))))));
      };
    case 8:
      return function() {
        return hi(gh(fg(ef(de(cd(bc(ab.apply(this, arguments))))))));
      };
    case 9:
      return function() {
        return ij(hi(gh(fg(ef(de(cd(bc(ab.apply(this, arguments)))))))));
      };
  }
  return;
}
function memoize(f) {
  const cache = new WeakMap;
  return (a) => {
    if (cache.has(a)) {
      return cache.get(a);
    }
    const result = f(a);
    cache.set(a, result);
    return result;
  };
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/equal.js
var getAllObjectKeys = (obj) => {
  const keys = new Set(Reflect.ownKeys(obj));
  if (obj.constructor === Object)
    return keys;
  if (obj instanceof Error) {
    keys.delete("stack");
  }
  const proto = Object.getPrototypeOf(obj);
  let current = proto;
  while (current !== null && current !== Object.prototype) {
    const ownKeys = Reflect.ownKeys(current);
    for (let i = 0;i < ownKeys.length; i++) {
      keys.add(ownKeys[i]);
    }
    current = Object.getPrototypeOf(current);
  }
  if (keys.has("constructor") && typeof obj.constructor === "function" && proto === obj.constructor.prototype) {
    keys.delete("constructor");
  }
  return keys;
};
var byReferenceInstances = /* @__PURE__ */ new WeakSet;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Predicate.js
function isString(input) {
  return typeof input === "string";
}
function isNumber(input) {
  return typeof input === "number";
}
function isBoolean(input) {
  return typeof input === "boolean";
}
function isBigInt(input) {
  return typeof input === "bigint";
}
function isSymbol(input) {
  return typeof input === "symbol";
}
function isPropertyKey(u) {
  return isString(u) || isNumber(u) || isSymbol(u);
}
function isFunction(input) {
  return typeof input === "function";
}
function isNotUndefined(input) {
  return input !== undefined;
}
function isNotNullish(input) {
  return input != null;
}
function isUnknown(_) {
  return true;
}
function isObjectKeyword(input) {
  return typeof input === "object" && input !== null || isFunction(input);
}
var hasProperty = /* @__PURE__ */ dual(2, (self, property) => isObjectKeyword(self) && (property in self));
var isTagged = /* @__PURE__ */ dual(2, (self, tag) => hasProperty(self, "_tag") && self["_tag"] === tag);
function isIterable(input) {
  return hasProperty(input, Symbol.iterator) || isString(input);
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Hash.js
var symbol = "~effect/interfaces/Hash";
var hash = (self) => {
  switch (typeof self) {
    case "number":
      return number(self);
    case "bigint":
      return string(self.toString(10));
    case "boolean":
      return string(String(self));
    case "symbol":
      return string(String(self));
    case "string":
      return string(self);
    case "undefined":
      return string("undefined");
    case "function":
    case "object": {
      if (self === null) {
        return string("null");
      } else if (self instanceof Date) {
        return string(self.toISOString());
      } else if (self instanceof RegExp) {
        return string(self.toString());
      } else {
        if (byReferenceInstances.has(self)) {
          return random(self);
        }
        if (hashCache.has(self)) {
          return hashCache.get(self);
        }
        const h = withVisitedTracking(self, () => {
          if (isHash(self)) {
            return self[symbol]();
          } else if (typeof self === "function") {
            return random(self);
          } else if (Array.isArray(self) || ArrayBuffer.isView(self)) {
            return array(self);
          } else if (self instanceof Map) {
            return hashMap(self);
          } else if (self instanceof Set) {
            return hashSet(self);
          }
          return structure(self);
        });
        hashCache.set(self, h);
        return h;
      }
    }
    default:
      throw new Error(`BUG: unhandled typeof ${typeof self} - please report an issue at https://github.com/Effect-TS/effect/issues`);
  }
};
var random = (self) => {
  if (!randomHashCache.has(self)) {
    randomHashCache.set(self, number(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER)));
  }
  return randomHashCache.get(self);
};
var combine = /* @__PURE__ */ dual(2, (self, b) => self * 53 ^ b);
var optimize = (n) => n & 3221225471 | n >>> 1 & 1073741824;
var isHash = (u) => hasProperty(u, symbol);
var number = (n) => {
  if (n !== n) {
    return string("NaN");
  }
  if (n === Infinity) {
    return string("Infinity");
  }
  if (n === -Infinity) {
    return string("-Infinity");
  }
  let h = n | 0;
  if (h !== n) {
    h ^= n * 4294967295;
  }
  while (n > 4294967295) {
    h ^= n /= 4294967295;
  }
  return optimize(h);
};
var string = (str) => {
  let h = 5381, i = str.length;
  while (i) {
    h = h * 33 ^ str.charCodeAt(--i);
  }
  return optimize(h);
};
var structureKeys = (o, keys) => {
  let h = 12289;
  for (const key of keys) {
    h ^= combine(hash(key), hash(o[key]));
  }
  return optimize(h);
};
var structure = (o) => structureKeys(o, getAllObjectKeys(o));
var iterableWith = (seed, f) => (iter) => {
  let h = seed;
  for (const element of iter) {
    h ^= f(element);
  }
  return optimize(h);
};
var array = /* @__PURE__ */ iterableWith(6151, hash);
var hashMap = /* @__PURE__ */ iterableWith(/* @__PURE__ */ string("Map"), ([k, v]) => combine(hash(k), hash(v)));
var hashSet = /* @__PURE__ */ iterableWith(/* @__PURE__ */ string("Set"), hash);
var randomHashCache = /* @__PURE__ */ new WeakMap;
var hashCache = /* @__PURE__ */ new WeakMap;
var visitedObjects = /* @__PURE__ */ new WeakSet;
function withVisitedTracking(obj, fn) {
  if (visitedObjects.has(obj)) {
    return string("[Circular]");
  }
  visitedObjects.add(obj);
  const result = fn();
  visitedObjects.delete(obj);
  return result;
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Equal.js
var symbol2 = "~effect/interfaces/Equal";
function equals() {
  if (arguments.length === 1) {
    return (self) => compareBoth(self, arguments[0]);
  }
  return compareBoth(arguments[0], arguments[1]);
}
function compareBoth(self, that) {
  if (self === that)
    return true;
  if (self == null || that == null)
    return false;
  const selfType = typeof self;
  if (selfType !== typeof that) {
    return false;
  }
  if (selfType === "number" && self !== self && that !== that) {
    return true;
  }
  if (selfType !== "object" && selfType !== "function") {
    return false;
  }
  if (byReferenceInstances.has(self) || byReferenceInstances.has(that)) {
    return false;
  }
  return withCache(self, that, compareObjects);
}
function withVisitedTracking2(self, that, fn) {
  const hasLeft = visitedLeft.has(self);
  const hasRight = visitedRight.has(that);
  if (hasLeft && hasRight) {
    return true;
  }
  if (hasLeft || hasRight) {
    return false;
  }
  visitedLeft.add(self);
  visitedRight.add(that);
  const result = fn();
  visitedLeft.delete(self);
  visitedRight.delete(that);
  return result;
}
var visitedLeft = /* @__PURE__ */ new WeakSet;
var visitedRight = /* @__PURE__ */ new WeakSet;
function compareObjects(self, that) {
  if (hash(self) !== hash(that)) {
    return false;
  } else if (self instanceof Date) {
    if (!(that instanceof Date))
      return false;
    return self.toISOString() === that.toISOString();
  } else if (self instanceof RegExp) {
    if (!(that instanceof RegExp))
      return false;
    return self.toString() === that.toString();
  }
  const selfIsEqual = isEqual(self);
  const thatIsEqual = isEqual(that);
  if (selfIsEqual !== thatIsEqual)
    return false;
  const bothEquals = selfIsEqual && thatIsEqual;
  if (typeof self === "function" && !bothEquals) {
    return false;
  }
  return withVisitedTracking2(self, that, () => {
    if (bothEquals) {
      return self[symbol2](that);
    } else if (Array.isArray(self)) {
      if (!Array.isArray(that) || self.length !== that.length) {
        return false;
      }
      return compareArrays(self, that);
    } else if (ArrayBuffer.isView(self)) {
      if (!ArrayBuffer.isView(that) || self.byteLength !== that.byteLength) {
        return false;
      }
      return compareTypedArrays(self, that);
    } else if (self instanceof Map) {
      if (!(that instanceof Map) || self.size !== that.size) {
        return false;
      }
      return compareMaps(self, that);
    } else if (self instanceof Set) {
      if (!(that instanceof Set) || self.size !== that.size) {
        return false;
      }
      return compareSets(self, that);
    }
    return compareRecords(self, that);
  });
}
function withCache(self, that, f) {
  let selfMap = equalityCache.get(self);
  if (!selfMap) {
    selfMap = new WeakMap;
    equalityCache.set(self, selfMap);
  } else if (selfMap.has(that)) {
    return selfMap.get(that);
  }
  const result = f(self, that);
  selfMap.set(that, result);
  let thatMap = equalityCache.get(that);
  if (!thatMap) {
    thatMap = new WeakMap;
    equalityCache.set(that, thatMap);
  }
  thatMap.set(self, result);
  return result;
}
var equalityCache = /* @__PURE__ */ new WeakMap;
function compareArrays(self, that) {
  for (let i = 0;i < self.length; i++) {
    if (!compareBoth(self[i], that[i])) {
      return false;
    }
  }
  return true;
}
function compareTypedArrays(self, that) {
  if (self.length !== that.length) {
    return false;
  }
  for (let i = 0;i < self.length; i++) {
    if (self[i] !== that[i]) {
      return false;
    }
  }
  return true;
}
function compareRecords(self, that) {
  const selfKeys = getAllObjectKeys(self);
  const thatKeys = getAllObjectKeys(that);
  if (selfKeys.size !== thatKeys.size) {
    return false;
  }
  for (const key of selfKeys) {
    if (!thatKeys.has(key) || !compareBoth(self[key], that[key])) {
      return false;
    }
  }
  return true;
}
function makeCompareMap(keyEquivalence, valueEquivalence) {
  return function compareMaps(self, that) {
    for (const [selfKey, selfValue] of self) {
      let found = false;
      for (const [thatKey, thatValue] of that) {
        if (keyEquivalence(selfKey, thatKey) && valueEquivalence(selfValue, thatValue)) {
          found = true;
          break;
        }
      }
      if (!found) {
        return false;
      }
    }
    return true;
  };
}
var compareMaps = /* @__PURE__ */ makeCompareMap(compareBoth, compareBoth);
function makeCompareSet(equivalence) {
  return function compareSets(self, that) {
    for (const selfValue of self) {
      let found = false;
      for (const thatValue of that) {
        if (equivalence(selfValue, thatValue)) {
          found = true;
          break;
        }
      }
      if (!found) {
        return false;
      }
    }
    return true;
  };
}
var compareSets = /* @__PURE__ */ makeCompareSet(compareBoth);
var isEqual = (u) => hasProperty(u, symbol2);
var asEquivalence = () => equals;
var byReferenceUnsafe = (obj) => {
  byReferenceInstances.add(obj);
  return obj;
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Equivalence.js
var make = (isEquivalent) => (self, that) => self === that || isEquivalent(self, that);

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/array.js
var isArrayNonEmpty = (self) => self.length > 0;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/doNotation.js
var let_ = (map) => dual(3, (self, name, f) => map(self, (a) => ({
  ...a,
  [name]: f(a)
})));
var bindTo = (map) => dual(2, (self, name) => map(self, (a) => ({
  [name]: a
})));
var bind = (map, flatMap) => dual(3, (self, name, f) => flatMap(self, (a) => map(f(a), (b) => ({
  ...a,
  [name]: b
}))));

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Redactable.js
var symbolRedactable = /* @__PURE__ */ Symbol.for("~effect/Redactable");
var isRedactable = (u) => hasProperty(u, symbolRedactable);
function redact(u) {
  if (isRedactable(u))
    return getRedacted(u);
  return u;
}
function getRedacted(redactable) {
  return redactable[symbolRedactable](globalThis[currentFiberTypeId]?.context ?? emptyContext);
}
var currentFiberTypeId = "~effect/Fiber/currentFiber";
var emptyContext = {
  "~effect/Context": {},
  mapUnsafe: /* @__PURE__ */ new Map,
  pipe() {
    return pipeArguments(this, arguments);
  }
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Formatter.js
function format(input, options) {
  const space = options?.space ?? 0;
  const seen = new WeakSet;
  const gap = !space ? "" : typeof space === "number" ? " ".repeat(space) : space;
  const ind = (d) => gap.repeat(d);
  const wrap = (v, body) => {
    const ctor = v?.constructor;
    return ctor && ctor !== Object.prototype.constructor && ctor.name ? `${ctor.name}(${body})` : body;
  };
  const ownKeys = (o) => {
    try {
      return Reflect.ownKeys(o);
    } catch {
      return ["[ownKeys threw]"];
    }
  };
  function recur(v, d = 0) {
    if (Array.isArray(v)) {
      if (seen.has(v))
        return CIRCULAR;
      seen.add(v);
      if (!gap || v.length <= 1)
        return `[${v.map((x) => recur(x, d)).join(",")}]`;
      const inner = v.map((x) => recur(x, d + 1)).join(`,
` + ind(d + 1));
      return `[
${ind(d + 1)}${inner}
${ind(d)}]`;
    }
    if (v instanceof Date)
      return formatDate(v);
    if (!options?.ignoreToString && hasProperty(v, "toString") && typeof v["toString"] === "function" && v["toString"] !== Object.prototype.toString && v["toString"] !== Array.prototype.toString) {
      const s = safeToString(v);
      if (v instanceof Error && v.cause) {
        return `${s} (cause: ${recur(v.cause, d)})`;
      }
      return s;
    }
    if (typeof v === "string")
      return JSON.stringify(v);
    if (typeof v === "number" || v == null || typeof v === "boolean" || typeof v === "symbol")
      return String(v);
    if (typeof v === "bigint")
      return String(v) + "n";
    if (typeof v === "object" || typeof v === "function") {
      if (seen.has(v))
        return CIRCULAR;
      seen.add(v);
      if (symbolRedactable in v)
        return format(getRedacted(v));
      if (Symbol.iterator in v) {
        return `${v.constructor.name}(${recur(Array.from(v), d)})`;
      }
      const keys = ownKeys(v);
      if (!gap || keys.length <= 1) {
        const body2 = `{${keys.map((k) => `${formatPropertyKey(k)}:${recur(v[k], d)}`).join(",")}}`;
        return wrap(v, body2);
      }
      const body = `{
${keys.map((k) => `${ind(d + 1)}${formatPropertyKey(k)}: ${recur(v[k], d + 1)}`).join(`,
`)}
${ind(d)}}`;
      return wrap(v, body);
    }
    return String(v);
  }
  return recur(input, 0);
}
var CIRCULAR = "[Circular]";
function formatPropertyKey(name) {
  return typeof name === "string" ? JSON.stringify(name) : String(name);
}
function formatPath(path) {
  return path.map((key) => `[${formatPropertyKey(key)}]`).join("");
}
function formatDate(date) {
  try {
    return date.toISOString();
  } catch {
    return "Invalid Date";
  }
}
function safeToString(input) {
  try {
    const s = input.toString();
    return typeof s === "string" ? s : String(s);
  } catch {
    return "[toString threw]";
  }
}
function formatJson(input, options) {
  let cache = [];
  const out = JSON.stringify(input, (_key, value) => typeof value === "object" && value !== null ? cache.includes(value) ? undefined : cache.push(value) && redact(value) : value, options?.space);
  cache = undefined;
  return out;
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Inspectable.js
var NodeInspectSymbol = /* @__PURE__ */ Symbol.for("nodejs.util.inspect.custom");
var toJson = (input) => {
  try {
    if (hasProperty(input, "toJSON") && isFunction(input["toJSON"]) && input["toJSON"].length === 0) {
      return input.toJSON();
    } else if (Array.isArray(input)) {
      return input.map(toJson);
    }
  } catch {
    return "[toJSON threw]";
  }
  return redact(input);
};
var toStringUnknown = (u, whitespace = 2) => {
  if (typeof u === "string") {
    return u;
  }
  try {
    return typeof u === "object" ? stringifyCircular(u, whitespace) : String(u);
  } catch {
    return String(u);
  }
};
var stringifyCircular = (obj, whitespace) => {
  let cache = [];
  const retVal = JSON.stringify(obj, (_key, value) => typeof value === "object" && value !== null ? cache.includes(value) ? undefined : cache.push(value) && redact(value) : value, whitespace);
  cache = undefined;
  return retVal;
};
var BaseProto = {
  toJSON() {
    return toJson(this);
  },
  [NodeInspectSymbol]() {
    return this.toJSON();
  },
  toString() {
    return format(this.toJSON());
  }
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Utils.js
class SingleShotGen {
  called = false;
  self;
  constructor(self) {
    this.self = self;
  }
  next(a) {
    return this.called ? {
      value: a,
      done: true
    } : (this.called = true, {
      value: this.self,
      done: false
    });
  }
  [Symbol.iterator]() {
    return new SingleShotGen(this.self);
  }
}
var InternalTypeId = "~effect/Utils/internal";
var standard = {
  [InternalTypeId]: (body) => {
    return body();
  }
};
var forced = {
  [InternalTypeId]: (body) => {
    try {
      return body();
    } finally {}
  }
};
var isNotOptimizedAway = /* @__PURE__ */ standard[InternalTypeId](() => new Error().stack)?.includes(InternalTypeId) === true;
var internalCall = isNotOptimizedAway ? standard[InternalTypeId] : forced[InternalTypeId];

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/core.js
var EffectTypeId = `~effect/Effect`;
var ExitTypeId = `~effect/Exit`;
var effectVariance = {
  _A: identity,
  _E: identity,
  _R: identity
};
var identifier = `${EffectTypeId}/identifier`;
var args = `${EffectTypeId}/args`;
var evaluate = `${EffectTypeId}/evaluate`;
var contA = `${EffectTypeId}/successCont`;
var contE = `${EffectTypeId}/failureCont`;
var contAll = `${EffectTypeId}/ensureCont`;
var Yield = /* @__PURE__ */ Symbol.for("effect/Effect/Yield");
var PipeInspectableProto = {
  pipe() {
    return pipeArguments(this, arguments);
  },
  toJSON() {
    return {
      ...this
    };
  },
  toString() {
    return format(this.toJSON(), {
      ignoreToString: true,
      space: 2
    });
  },
  [NodeInspectSymbol]() {
    return this.toJSON();
  }
};
var StructuralProto = {
  [symbol]() {
    return structureKeys(this, Object.keys(this));
  },
  [symbol2](that) {
    const selfKeys = Object.keys(this);
    const thatKeys = Object.keys(that);
    if (selfKeys.length !== thatKeys.length)
      return false;
    for (let i = 0;i < selfKeys.length; i++) {
      if (selfKeys[i] !== thatKeys[i] && !equals(this[selfKeys[i]], that[selfKeys[i]])) {
        return false;
      }
    }
    return true;
  }
};
var YieldableProto = {
  [Symbol.iterator]() {
    return new SingleShotGen(this);
  }
};
var YieldableErrorProto = {
  ...YieldableProto,
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var EffectProto = {
  [EffectTypeId]: effectVariance,
  ...PipeInspectableProto,
  [Symbol.iterator]() {
    return new SingleShotGen(this);
  },
  asEffect() {
    return this;
  },
  toJSON() {
    return {
      _id: "Effect",
      op: this[identifier],
      ...args in this ? {
        args: this[args]
      } : undefined
    };
  }
};
var isEffect = (u) => hasProperty(u, EffectTypeId);
var isExit = (u) => hasProperty(u, ExitTypeId);
var CauseTypeId = "~effect/Cause";
var CauseReasonTypeId = "~effect/Cause/Reason";
var isCause = (self) => hasProperty(self, CauseTypeId);
class CauseImpl {
  [CauseTypeId];
  reasons;
  constructor(failures) {
    this[CauseTypeId] = CauseTypeId;
    this.reasons = failures;
  }
  pipe() {
    return pipeArguments(this, arguments);
  }
  toJSON() {
    return {
      _id: "Cause",
      failures: this.reasons.map((f) => f.toJSON())
    };
  }
  toString() {
    return `Cause(${format(this.reasons)})`;
  }
  [NodeInspectSymbol]() {
    return this.toJSON();
  }
  [symbol2](that) {
    return isCause(that) && this.reasons.length === that.reasons.length && this.reasons.every((e, i) => equals(e, that.reasons[i]));
  }
  [symbol]() {
    return array(this.reasons);
  }
}
var annotationsMap = /* @__PURE__ */ new WeakMap;

class ReasonBase {
  [CauseReasonTypeId];
  annotations;
  _tag;
  constructor(_tag, annotations, originalError) {
    this[CauseReasonTypeId] = CauseReasonTypeId;
    this._tag = _tag;
    if (annotations !== constEmptyAnnotations && typeof originalError === "object" && originalError !== null && annotations.size > 0) {
      const prevAnnotations = annotationsMap.get(originalError);
      if (prevAnnotations) {
        annotations = new Map([...prevAnnotations, ...annotations]);
      }
      annotationsMap.set(originalError, annotations);
    }
    this.annotations = annotations;
  }
  annotate(annotations, options) {
    if (annotations.mapUnsafe.size === 0)
      return this;
    const newAnnotations = new Map(this.annotations);
    annotations.mapUnsafe.forEach((value, key) => {
      if (options?.overwrite !== true && newAnnotations.has(key))
        return;
      newAnnotations.set(key, value);
    });
    const self = Object.assign(Object.create(Object.getPrototypeOf(this)), this);
    self.annotations = newAnnotations;
    return self;
  }
  pipe() {
    return pipeArguments(this, arguments);
  }
  toString() {
    return format(this);
  }
  [NodeInspectSymbol]() {
    return this.toString();
  }
}
var constEmptyAnnotations = /* @__PURE__ */ new Map;

class Fail extends ReasonBase {
  error;
  constructor(error, annotations = constEmptyAnnotations) {
    super("Fail", annotations, error);
    this.error = error;
  }
  toString() {
    return `Fail(${format(this.error)})`;
  }
  toJSON() {
    return {
      _tag: "Fail",
      error: this.error
    };
  }
  [symbol2](that) {
    return isFailReason(that) && equals(this.error, that.error) && equals(this.annotations, that.annotations);
  }
  [symbol]() {
    return combine(string(this._tag))(combine(hash(this.error))(hash(this.annotations)));
  }
}
var causeFromReasons = (reasons) => new CauseImpl(reasons);
var causeEmpty = /* @__PURE__ */ new CauseImpl([]);
var causeFail = (error) => new CauseImpl([new Fail(error)]);

class Die extends ReasonBase {
  defect;
  constructor(defect, annotations = constEmptyAnnotations) {
    super("Die", annotations, defect);
    this.defect = defect;
  }
  toString() {
    return `Die(${format(this.defect)})`;
  }
  toJSON() {
    return {
      _tag: "Die",
      defect: this.defect
    };
  }
  [symbol2](that) {
    return isDieReason(that) && equals(this.defect, that.defect) && equals(this.annotations, that.annotations);
  }
  [symbol]() {
    return combine(string(this._tag))(combine(hash(this.defect))(hash(this.annotations)));
  }
}
var causeDie = (defect) => new CauseImpl([new Die(defect)]);
var causeAnnotate = /* @__PURE__ */ dual((args2) => isCause(args2[0]), (self, annotations, options) => {
  if (annotations.mapUnsafe.size === 0)
    return self;
  return new CauseImpl(self.reasons.map((f) => f.annotate(annotations, options)));
});
var isFailReason = (self) => self._tag === "Fail";
var isDieReason = (self) => self._tag === "Die";
var isInterruptReason = (self) => self._tag === "Interrupt";
function defaultEvaluate(_fiber) {
  return exitDie(`Effect.evaluate: Not implemented`);
}
var makePrimitiveProto = (options) => ({
  ...EffectProto,
  [identifier]: options.op,
  [evaluate]: options[evaluate] ?? defaultEvaluate,
  [contA]: options[contA],
  [contE]: options[contE],
  [contAll]: options[contAll]
});
var makePrimitive = (options) => {
  const Proto = makePrimitiveProto(options);
  return function() {
    const self = Object.create(Proto);
    self[args] = options.single === false ? arguments : arguments[0];
    return self;
  };
};
var makeExit = (options) => {
  const Proto = {
    ...makePrimitiveProto(options),
    [ExitTypeId]: ExitTypeId,
    _tag: options.op,
    get [options.prop]() {
      return this[args];
    },
    toString() {
      return `${options.op}(${format(this[args])})`;
    },
    toJSON() {
      return {
        _id: "Exit",
        _tag: options.op,
        [options.prop]: this[args]
      };
    },
    [symbol2](that) {
      return isExit(that) && that._tag === this._tag && equals(this[args], that[args]);
    },
    [symbol]() {
      return combine(string(options.op), hash(this[args]));
    }
  };
  return function(value) {
    const self = Object.create(Proto);
    self[args] = value;
    return self;
  };
};
var exitSucceed = /* @__PURE__ */ makeExit({
  op: "Success",
  prop: "value",
  [evaluate](fiber) {
    const cont = fiber.getCont(contA);
    return cont ? cont[contA](this[args], fiber, this) : fiber.yieldWith(this);
  }
});
var StackTraceKey = {
  key: "effect/Cause/StackTrace"
};
var InterruptorStackTrace = {
  key: "effect/Cause/InterruptorStackTrace"
};
var exitFailCause = /* @__PURE__ */ makeExit({
  op: "Failure",
  prop: "cause",
  [evaluate](fiber) {
    let cause = this[args];
    let annotated = false;
    if (fiber.currentStackFrame) {
      cause = causeAnnotate(cause, {
        mapUnsafe: new Map([[StackTraceKey.key, fiber.currentStackFrame]])
      });
      annotated = true;
    }
    let cont = fiber.getCont(contE);
    while (fiber.interruptible && fiber._interruptedCause && cont) {
      cont = fiber.getCont(contE);
    }
    return cont ? cont[contE](cause, fiber, annotated ? undefined : this) : fiber.yieldWith(annotated ? this : exitFailCause(cause));
  }
});
var exitFail = (e) => exitFailCause(causeFail(e));
var exitDie = (defect) => exitFailCause(causeDie(defect));
var withFiber = /* @__PURE__ */ makePrimitive({
  op: "WithFiber",
  [evaluate](fiber) {
    return this[args](fiber);
  }
});
var YieldableError = /* @__PURE__ */ function() {

  class YieldableError2 extends globalThis.Error {
    asEffect() {
      return exitFail(this);
    }
  }
  Object.assign(YieldableError2.prototype, YieldableErrorProto);
  return YieldableError2;
}();
var Error2 = /* @__PURE__ */ function() {
  const plainArgsSymbol = /* @__PURE__ */ Symbol.for("effect/Data/Error/plainArgs");
  return class Base extends YieldableError {
    constructor(args2) {
      super(args2?.message, args2?.cause ? {
        cause: args2.cause
      } : undefined);
      if (args2) {
        Object.assign(this, args2);
        Object.defineProperty(this, plainArgsSymbol, {
          value: args2,
          enumerable: false
        });
      }
    }
    toJSON() {
      return {
        ...this[plainArgsSymbol],
        ...this
      };
    }
  };
}();
var TaggedError = (tag) => {

  class Base extends Error2 {
    _tag = tag;
  }
  Base.prototype.name = tag;
  return Base;
};
var NoSuchElementErrorTypeId = "~effect/Cause/NoSuchElementError";
var isNoSuchElementError = (u) => hasProperty(u, NoSuchElementErrorTypeId);

class NoSuchElementError extends (/* @__PURE__ */ TaggedError("NoSuchElementError")) {
  [NoSuchElementErrorTypeId] = NoSuchElementErrorTypeId;
  constructor(message) {
    super({
      message
    });
  }
}
var DoneTypeId = "~effect/Cause/Done";
var isDone = (u) => hasProperty(u, DoneTypeId);
var DoneVoid = {
  [DoneTypeId]: DoneTypeId,
  _tag: "Done",
  value: undefined
};
var Done = (value) => {
  if (value === undefined)
    return DoneVoid;
  return {
    [DoneTypeId]: DoneTypeId,
    _tag: "Done",
    value
  };
};
var doneVoid = /* @__PURE__ */ exitFail(DoneVoid);
var done = (value) => {
  if (value === undefined)
    return doneVoid;
  return exitFail(Done(value));
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/option.js
var TypeId = "~effect/data/Option";
var CommonProto = {
  [TypeId]: {
    _A: (_) => _
  },
  ...PipeInspectableProto,
  ...YieldableProto
};
var SomeProto = /* @__PURE__ */ Object.assign(/* @__PURE__ */ Object.create(CommonProto), {
  _tag: "Some",
  _op: "Some",
  [symbol2](that) {
    return isOption(that) && isSome(that) && equals(this.value, that.value);
  },
  [symbol]() {
    return combine(hash(this._tag))(hash(this.value));
  },
  toString() {
    return `some(${format(this.value)})`;
  },
  toJSON() {
    return {
      _id: "Option",
      _tag: this._tag,
      value: toJson(this.value)
    };
  },
  asEffect() {
    return exitSucceed(this.value);
  }
});
Object.defineProperty(SomeProto, "valueOrUndefined", {
  get() {
    return this.value;
  }
});
var NoneHash = /* @__PURE__ */ hash("None");
var NoneProto = /* @__PURE__ */ Object.assign(/* @__PURE__ */ Object.create(CommonProto), {
  _tag: "None",
  _op: "None",
  valueOrUndefined: undefined,
  [symbol2](that) {
    return isOption(that) && isNone(that);
  },
  [symbol]() {
    return NoneHash;
  },
  toString() {
    return `none()`;
  },
  toJSON() {
    return {
      _id: "Option",
      _tag: this._tag
    };
  },
  asEffect() {
    return exitFail(new NoSuchElementError);
  }
});
var isOption = (input) => hasProperty(input, TypeId);
var isNone = (fa) => fa._tag === "None";
var isSome = (fa) => fa._tag === "Some";
var none = /* @__PURE__ */ Object.create(NoneProto);
var some = (value) => {
  const a = Object.create(SomeProto);
  a.value = value;
  return a;
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/result.js
var TypeId2 = "~effect/data/Result";
var CommonProto2 = {
  [TypeId2]: {
    _A: (_) => _,
    _E: (_) => _
  },
  ...PipeInspectableProto,
  ...YieldableProto
};
var SuccessProto = /* @__PURE__ */ Object.assign(/* @__PURE__ */ Object.create(CommonProto2), {
  _tag: "Success",
  _op: "Success",
  [symbol2](that) {
    return isResult(that) && isSuccess(that) && equals(this.success, that.success);
  },
  [symbol]() {
    return combine(hash(this._tag))(hash(this.success));
  },
  toString() {
    return `success(${format(this.success)})`;
  },
  toJSON() {
    return {
      _id: "Result",
      _tag: this._tag,
      value: toJson(this.success)
    };
  },
  asEffect() {
    return exitSucceed(this.success);
  }
});
var FailureProto = /* @__PURE__ */ Object.assign(/* @__PURE__ */ Object.create(CommonProto2), {
  _tag: "Failure",
  _op: "Failure",
  [symbol2](that) {
    return isResult(that) && isFailure(that) && equals(this.failure, that.failure);
  },
  [symbol]() {
    return combine(hash(this._tag))(hash(this.failure));
  },
  toString() {
    return `failure(${format(this.failure)})`;
  },
  toJSON() {
    return {
      _id: "Result",
      _tag: this._tag,
      failure: toJson(this.failure)
    };
  },
  asEffect() {
    return exitFail(this.failure);
  }
});
var isResult = (input) => hasProperty(input, TypeId2);
var isFailure = (result) => result._tag === "Failure";
var isSuccess = (result) => result._tag === "Success";
var fail = (failure) => {
  const a = Object.create(FailureProto);
  a.failure = failure;
  return a;
};
var succeed = (success) => {
  const a = Object.create(SuccessProto);
  a.success = success;
  return a;
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Order.js
function make2(compare) {
  return (self, that) => self === that ? 0 : compare(self, that);
}
var Number2 = /* @__PURE__ */ make2((self, that) => {
  if (globalThis.Number.isNaN(self) && globalThis.Number.isNaN(that))
    return 0;
  if (globalThis.Number.isNaN(self))
    return -1;
  if (globalThis.Number.isNaN(that))
    return 1;
  return self < that ? -1 : 1;
});
var mapInput = /* @__PURE__ */ dual(2, (self, f) => make2((b1, b2) => self(f(b1), f(b2))));
var isLessThan = (O) => dual(2, (self, that) => O(self, that) === -1);
var isGreaterThan = (O) => dual(2, (self, that) => O(self, that) === 1);
var isLessThanOrEqualTo = (O) => dual(2, (self, that) => O(self, that) !== 1);
var isGreaterThanOrEqualTo = (O) => dual(2, (self, that) => O(self, that) !== -1);

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Option.js
var none2 = () => none;
var some2 = some;
var isNone2 = isNone;
var isSome2 = isSome;
var match = /* @__PURE__ */ dual(2, (self, {
  onNone,
  onSome
}) => isNone2(self) ? onNone() : onSome(self.value));
var getOrElse = /* @__PURE__ */ dual(2, (self, onNone) => isNone2(self) ? onNone() : self.value);
var getOrUndefined = /* @__PURE__ */ getOrElse(constUndefined);
var liftThrowable = (f) => (...a) => {
  try {
    return some2(f(...a));
  } catch {
    return none2();
  }
};
var map = /* @__PURE__ */ dual(2, (self, f) => isNone2(self) ? none2() : some2(f(self.value)));
var filter = /* @__PURE__ */ dual(2, (self, predicate) => isNone2(self) ? none2() : predicate(self.value) ? some2(self.value) : none2());

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Result.js
var succeed2 = succeed;
var fail2 = fail;
var isFailure2 = isFailure;
var isSuccess2 = isSuccess;
var mapError = /* @__PURE__ */ dual(2, (self, f) => isFailure2(self) ? fail2(f(self.failure)) : succeed2(self.success));
var match2 = /* @__PURE__ */ dual(2, (self, {
  onFailure,
  onSuccess
}) => isFailure2(self) ? onFailure(self.failure) : onSuccess(self.success));

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Iterable.js
var constEmpty = {
  [Symbol.iterator]() {
    return constEmptyIterator;
  }
};
var constEmptyIterator = {
  next() {
    return {
      done: true,
      value: undefined
    };
  }
};
var filter2 = /* @__PURE__ */ dual(2, (self, predicate) => ({
  [Symbol.iterator]() {
    const iterator = self[Symbol.iterator]();
    let i = 0;
    return {
      next() {
        let result = iterator.next();
        while (!result.done) {
          if (predicate(result.value, i++)) {
            return {
              done: false,
              value: result.value
            };
          }
          result = iterator.next();
        }
        return {
          done: true,
          value: undefined
        };
      }
    };
  }
}));

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Record.js
var map2 = /* @__PURE__ */ dual(2, (self, f) => {
  const out = {
    ...self
  };
  for (const key of keys(self)) {
    out[key] = f(self[key], key);
  }
  return out;
});
var keys = (self) => Object.keys(self);

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Array.js
var Array2 = globalThis.Array;
var allocate = (n) => new Array2(n);
var fromIterable = (collection) => Array2.isArray(collection) ? collection : Array2.from(collection);
var append = /* @__PURE__ */ dual(2, (self, last) => [...self, last]);
var appendAll = /* @__PURE__ */ dual(2, (self, that) => fromIterable(self).concat(fromIterable(that)));
var isArray = Array2.isArray;
var isArrayNonEmpty2 = isArrayNonEmpty;
var isReadonlyArrayNonEmpty = isArrayNonEmpty;
function isOutOfBounds(i, as) {
  return i < 0 || i >= as.length;
}
var getUnsafe = /* @__PURE__ */ dual(2, (self, index) => {
  const i = Math.floor(index);
  if (isOutOfBounds(i, self)) {
    throw new Error(`Index out of bounds: ${i}`);
  }
  return self[i];
});
var headNonEmpty = /* @__PURE__ */ getUnsafe(0);
var tailNonEmpty = (self) => self.slice(1);
var sort = /* @__PURE__ */ dual(2, (self, O) => {
  const out = Array2.from(self);
  out.sort(O);
  return out;
});
var unionWith = /* @__PURE__ */ dual(3, (self, that, isEquivalent) => {
  const a = fromIterable(self);
  const b = fromIterable(that);
  if (isReadonlyArrayNonEmpty(a)) {
    if (isReadonlyArrayNonEmpty(b)) {
      const dedupe = dedupeWith(isEquivalent);
      return dedupe(appendAll(a, b));
    }
    return a;
  }
  return b;
});
var union = /* @__PURE__ */ dual(2, (self, that) => unionWith(self, that, asEquivalence()));
var empty = () => [];
var map3 = /* @__PURE__ */ dual(2, (self, f) => self.map(f));
var partition = /* @__PURE__ */ dual(2, (self, f) => {
  const excluded = [];
  const satisfying = [];
  let i = 0;
  for (const a of self) {
    const result = f(a, i++);
    if (isSuccess2(result)) {
      satisfying.push(result.success);
    } else {
      excluded.push(result.failure);
    }
  }
  return [excluded, satisfying];
});
var dedupeWith = /* @__PURE__ */ dual(2, (self, isEquivalent) => {
  const input = fromIterable(self);
  if (isReadonlyArrayNonEmpty(input)) {
    const out = [headNonEmpty(input)];
    const rest = tailNonEmpty(input);
    for (const r of rest) {
      if (out.every((a) => !isEquivalent(r, a))) {
        out.push(r);
      }
    }
    return out;
  }
  return [];
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Context.js
var exports_Context = {};
__export(exports_Context, {
  pick: () => pick,
  omit: () => omit,
  mutate: () => mutate,
  mergeAll: () => mergeAll,
  merge: () => merge,
  makeUnsafe: () => makeUnsafe,
  make: () => make3,
  isReference: () => isReference,
  isKey: () => isKey,
  isContext: () => isContext,
  getUnsafe: () => getUnsafe2,
  getReferenceUnsafe: () => getReferenceUnsafe,
  getOrUndefined: () => getOrUndefined2,
  getOrElse: () => getOrElse2,
  getOption: () => getOption,
  get: () => get,
  empty: () => empty2,
  addOrOmit: () => addOrOmit,
  add: () => add,
  ServiceTypeId: () => ServiceTypeId,
  Service: () => Service,
  Reference: () => Reference
});
var ServiceTypeId = "~effect/Context/Service";
var Service = function() {
  const prevLimit = Error.stackTraceLimit;
  Error.stackTraceLimit = 2;
  const err = new Error;
  Error.stackTraceLimit = prevLimit;
  function KeyClass() {}
  const self = KeyClass;
  Object.setPrototypeOf(self, ServiceProto);
  Object.defineProperty(self, "stack", {
    get() {
      return err.stack;
    }
  });
  if (arguments.length > 0) {
    self.key = arguments[0];
    if (arguments[1]?.defaultValue) {
      self[ReferenceTypeId] = ReferenceTypeId;
      self.defaultValue = arguments[1].defaultValue;
    }
    return self;
  }
  return function(key, options) {
    self.key = key;
    if (options?.make) {
      self.make = options.make;
    }
    return self;
  };
};
var ServiceProto = {
  [ServiceTypeId]: ServiceTypeId,
  ...PipeInspectableProto,
  ...YieldableProto,
  toJSON() {
    return {
      _id: "Service",
      key: this.key,
      stack: this.stack
    };
  },
  asEffect() {
    const fn = this.asEffect = constant(withFiber((fiber) => exitSucceed(get(fiber.context, this))));
    return fn();
  },
  of(self) {
    return self;
  },
  context(self) {
    return make3(this, self);
  },
  use(f) {
    return withFiber((fiber) => f(get(fiber.context, this)));
  },
  useSync(f) {
    return withFiber((fiber) => exitSucceed(f(get(fiber.context, this))));
  }
};
var ReferenceTypeId = "~effect/Context/Reference";
var TypeId3 = "~effect/Context";
var makeUnsafe = (mapUnsafe) => {
  const self = Object.create(Proto);
  self.mapUnsafe = mapUnsafe;
  self.mutable = false;
  return self;
};
var Proto = {
  ...PipeInspectableProto,
  [TypeId3]: {
    _Services: (_) => _
  },
  toJSON() {
    return {
      _id: "Context",
      services: Array.from(this.mapUnsafe).map(([key, value]) => ({
        key,
        value
      }))
    };
  },
  [symbol2](that) {
    if (!isContext(that) || this.mapUnsafe.size !== that.mapUnsafe.size)
      return false;
    for (const k of this.mapUnsafe.keys()) {
      if (!that.mapUnsafe.has(k) || !equals(this.mapUnsafe.get(k), that.mapUnsafe.get(k))) {
        return false;
      }
    }
    return true;
  },
  [symbol]() {
    return number(this.mapUnsafe.size);
  }
};
var isContext = (u) => hasProperty(u, TypeId3);
var isKey = (u) => hasProperty(u, ServiceTypeId);
var isReference = (u) => hasProperty(u, ReferenceTypeId);
var empty2 = () => emptyContext2;
var emptyContext2 = /* @__PURE__ */ makeUnsafe(/* @__PURE__ */ new Map);
var make3 = (key, service) => makeUnsafe(new Map([[key.key, service]]));
var add = /* @__PURE__ */ dual(3, (self, key, service) => withMapUnsafe(self, (map4) => {
  map4.set(key.key, service);
}));
var addOrOmit = /* @__PURE__ */ dual(3, (self, key, service) => withMapUnsafe(self, (map4) => {
  if (service._tag === "None") {
    map4.delete(key.key);
  } else {
    map4.set(key.key, service.value);
  }
}));
var getOrElse2 = /* @__PURE__ */ dual(3, (self, key, orElse) => {
  if (self.mapUnsafe.has(key.key)) {
    return self.mapUnsafe.get(key.key);
  }
  return isReference(key) ? getDefaultValue(key) : orElse();
});
var getOrUndefined2 = /* @__PURE__ */ dual(2, (self, key) => self.mapUnsafe.get(key.key));
var getUnsafe2 = /* @__PURE__ */ dual(2, (self, service) => {
  if (!self.mapUnsafe.has(service.key)) {
    if (ReferenceTypeId in service)
      return getDefaultValue(service);
    throw serviceNotFoundError(service);
  }
  return self.mapUnsafe.get(service.key);
});
var get = getUnsafe2;
var getReferenceUnsafe = (self, service) => {
  if (!self.mapUnsafe.has(service.key)) {
    return getDefaultValue(service);
  }
  return self.mapUnsafe.get(service.key);
};
var defaultValueCacheKey = "~effect/Context/defaultValue";
var getDefaultValue = (ref) => {
  if (defaultValueCacheKey in ref) {
    return ref[defaultValueCacheKey];
  }
  return ref[defaultValueCacheKey] = ref.defaultValue();
};
var serviceNotFoundError = (service) => {
  const error = new Error(`Service not found${service.key ? `: ${String(service.key)}` : ""}`);
  if (service.stack) {
    const lines = service.stack.split(`
`);
    if (lines.length > 2) {
      const afterAt = lines[2].match(/at (.*)/);
      if (afterAt) {
        error.message = error.message + ` (defined at ${afterAt[1]})`;
      }
    }
  }
  if (error.stack) {
    const lines = error.stack.split(`
`);
    lines.splice(1, 3);
    error.stack = lines.join(`
`);
  }
  return error;
};
var getOption = /* @__PURE__ */ dual(2, (self, service) => {
  if (self.mapUnsafe.has(service.key)) {
    return some2(self.mapUnsafe.get(service.key));
  }
  return isReference(service) ? some2(getDefaultValue(service)) : none2();
});
var merge = /* @__PURE__ */ dual(2, (self, that) => {
  if (self.mapUnsafe.size === 0)
    return that;
  if (that.mapUnsafe.size === 0)
    return self;
  return withMapUnsafe(self, (map4) => {
    that.mapUnsafe.forEach((value, key) => map4.set(key, value));
  });
});
var mergeAll = (...ctxs) => {
  const map4 = new Map;
  for (let i = 0;i < ctxs.length; i++) {
    ctxs[i].mapUnsafe.forEach((value, key) => {
      map4.set(key, value);
    });
  }
  return makeUnsafe(map4);
};
var pick = (...services) => (self) => withMapUnsafe(self, (map4) => {
  const keySet = new Set(services.map((key) => key.key));
  map4.forEach((_, key) => {
    if (keySet.has(key))
      return;
    map4.delete(key);
  });
});
var omit = (...keys2) => (self) => withMapUnsafe(self, (map4) => {
  for (let i = 0;i < keys2.length; i++) {
    map4.delete(keys2[i].key);
  }
});
var mutate = /* @__PURE__ */ dual(2, (self, f) => {
  const next = makeUnsafe(new Map(self.mapUnsafe));
  next.mutable = true;
  const result = f(next);
  result.mutable = false;
  return result;
});
var withMapUnsafe = (self, f) => {
  if (self.mutable) {
    f(self.mapUnsafe);
    return self;
  }
  const map4 = new Map(self.mapUnsafe);
  f(map4);
  return makeUnsafe(map4);
};
var Reference = Service;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Duration.js
var TypeId4 = "~effect/time/Duration";
var bigint0 = /* @__PURE__ */ BigInt(0);
var bigint1e3 = /* @__PURE__ */ BigInt(1000);
var bigint1e6 = /* @__PURE__ */ BigInt(1e6);
var DURATION_REGEXP = /^(-?\d+(?:\.\d+)?)\s+(nanos?|micros?|millis?|seconds?|minutes?|hours?|days?|weeks?)$/;
var fromInputUnsafe = (input) => {
  switch (typeof input) {
    case "number":
      return millis(input);
    case "bigint":
      return nanos(input);
    case "string": {
      const match3 = DURATION_REGEXP.exec(input);
      if (!match3)
        break;
      const [_, valueStr, unit] = match3;
      const value = Number(valueStr);
      switch (unit) {
        case "nano":
        case "nanos":
          return nanos(BigInt(valueStr));
        case "micro":
        case "micros":
          return micros(BigInt(valueStr));
        case "milli":
        case "millis":
          return millis(value);
        case "second":
        case "seconds":
          return seconds(value);
        case "minute":
        case "minutes":
          return minutes(value);
        case "hour":
        case "hours":
          return hours(value);
        case "day":
        case "days":
          return days(value);
        case "week":
        case "weeks":
          return weeks(value);
      }
      break;
    }
    case "object": {
      if (input === null)
        break;
      if (TypeId4 in input)
        return input;
      if (Array.isArray(input)) {
        if (input.length !== 2 || !input.every(isNumber)) {
          return invalid(input);
        }
        if (Number.isNaN(input[0]) || Number.isNaN(input[1])) {
          return zero;
        }
        if (input[0] === -Infinity || input[1] === -Infinity) {
          return negativeInfinity;
        }
        if (input[0] === Infinity || input[1] === Infinity) {
          return infinity;
        }
        return make4(BigInt(Math.round(input[0] * 1e9)) + BigInt(Math.round(input[1])));
      }
      const obj = input;
      let millis = 0;
      if (obj.weeks)
        millis += obj.weeks * 604800000;
      if (obj.days)
        millis += obj.days * 86400000;
      if (obj.hours)
        millis += obj.hours * 3600000;
      if (obj.minutes)
        millis += obj.minutes * 60000;
      if (obj.seconds)
        millis += obj.seconds * 1000;
      if (obj.milliseconds)
        millis += obj.milliseconds;
      if (!obj.microseconds && !obj.nanoseconds)
        return make4(millis);
      let nanos = BigInt(millis) * bigint1e6;
      if (obj.microseconds)
        nanos += BigInt(obj.microseconds) * bigint1e3;
      if (obj.nanoseconds)
        nanos += BigInt(obj.nanoseconds);
      return make4(nanos);
    }
  }
  return invalid(input);
};
var invalid = (input) => {
  throw new Error(`Invalid Input: ${input}`);
};
var fromInput = /* @__PURE__ */ liftThrowable(fromInputUnsafe);
var zeroDurationValue = {
  _tag: "Millis",
  millis: 0
};
var infinityDurationValue = {
  _tag: "Infinity"
};
var negativeInfinityDurationValue = {
  _tag: "NegativeInfinity"
};
var DurationProto = {
  [TypeId4]: TypeId4,
  [symbol]() {
    return structure(this.value);
  },
  [symbol2](that) {
    return isDuration(that) && equals2(this, that);
  },
  toString() {
    switch (this.value._tag) {
      case "Infinity":
        return "Infinity";
      case "NegativeInfinity":
        return "-Infinity";
      case "Nanos":
        return `${this.value.nanos} nanos`;
      case "Millis":
        return `${this.value.millis} millis`;
    }
  },
  toJSON() {
    switch (this.value._tag) {
      case "Millis":
        return {
          _id: "Duration",
          _tag: "Millis",
          millis: this.value.millis
        };
      case "Nanos":
        return {
          _id: "Duration",
          _tag: "Nanos",
          nanos: String(this.value.nanos)
        };
      case "Infinity":
        return {
          _id: "Duration",
          _tag: "Infinity"
        };
      case "NegativeInfinity":
        return {
          _id: "Duration",
          _tag: "NegativeInfinity"
        };
    }
  },
  [NodeInspectSymbol]() {
    return this.toJSON();
  },
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var make4 = (input) => {
  const duration = Object.create(DurationProto);
  if (typeof input === "number") {
    if (isNaN(input) || input === 0 || Object.is(input, -0)) {
      duration.value = zeroDurationValue;
    } else if (!Number.isFinite(input)) {
      duration.value = input > 0 ? infinityDurationValue : negativeInfinityDurationValue;
    } else if (!Number.isInteger(input)) {
      duration.value = {
        _tag: "Nanos",
        nanos: BigInt(Math.round(input * 1e6))
      };
    } else {
      duration.value = {
        _tag: "Millis",
        millis: input
      };
    }
  } else if (input === bigint0) {
    duration.value = zeroDurationValue;
  } else {
    duration.value = {
      _tag: "Nanos",
      nanos: input
    };
  }
  return duration;
};
var isDuration = (u) => hasProperty(u, TypeId4);
var zero = /* @__PURE__ */ make4(0);
var infinity = /* @__PURE__ */ make4(Infinity);
var negativeInfinity = /* @__PURE__ */ make4(-Infinity);
var nanos = (nanos2) => make4(nanos2);
var micros = (micros2) => make4(micros2 * bigint1e3);
var millis = (millis2) => make4(millis2);
var seconds = (seconds2) => make4(seconds2 * 1000);
var minutes = (minutes2) => make4(minutes2 * 60000);
var hours = (hours2) => make4(hours2 * 3600000);
var days = (days2) => make4(days2 * 86400000);
var weeks = (weeks2) => make4(weeks2 * 604800000);
var toMillis = (self) => match3(self, {
  onMillis: identity,
  onNanos: (nanos2) => Number(nanos2) / 1e6,
  onInfinity: () => Infinity,
  onNegativeInfinity: () => -Infinity
});
var toNanosUnsafe = (self) => {
  switch (self.value._tag) {
    case "Infinity":
    case "NegativeInfinity":
      throw new Error("Cannot convert infinite duration to nanos");
    case "Nanos":
      return self.value.nanos;
    case "Millis":
      return BigInt(Math.round(self.value.millis * 1e6));
  }
};
var match3 = /* @__PURE__ */ dual(2, (self, options) => {
  switch (self.value._tag) {
    case "Millis":
      return options.onMillis(self.value.millis);
    case "Nanos":
      return options.onNanos(self.value.nanos);
    case "Infinity":
      return options.onInfinity();
    case "NegativeInfinity":
      return (options.onNegativeInfinity ?? options.onInfinity)();
  }
});
var matchPair = /* @__PURE__ */ dual(3, (self, that, options) => {
  if (self.value._tag === "Infinity" || self.value._tag === "NegativeInfinity" || that.value._tag === "Infinity" || that.value._tag === "NegativeInfinity")
    return options.onInfinity(self, that);
  if (self.value._tag === "Millis") {
    return that.value._tag === "Millis" ? options.onMillis(self.value.millis, that.value.millis) : options.onNanos(toNanosUnsafe(self), that.value.nanos);
  } else {
    return options.onNanos(self.value.nanos, toNanosUnsafe(that));
  }
});
var Equivalence = (self, that) => matchPair(self, that, {
  onMillis: (self2, that2) => self2 === that2,
  onNanos: (self2, that2) => self2 === that2,
  onInfinity: (self2, that2) => self2.value._tag === that2.value._tag
});
var subtract = /* @__PURE__ */ dual(2, (self, that) => matchPair(self, that, {
  onMillis: (self2, that2) => make4(self2 - that2),
  onNanos: (self2, that2) => make4(self2 - that2),
  onInfinity: (self2, that2) => {
    const s = self2.value._tag;
    const t = that2.value._tag;
    if (s === "Infinity")
      return t === "Infinity" ? zero : infinity;
    if (s === "NegativeInfinity")
      return t === "NegativeInfinity" ? zero : negativeInfinity;
    return t === "Infinity" ? negativeInfinity : infinity;
  }
}));
var equals2 = /* @__PURE__ */ dual(2, (self, that) => Equivalence(self, that));

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Filter.js
var composePassthrough = /* @__PURE__ */ dual(2, (left, right) => (input) => {
  const leftOut = left(input);
  if (isFailure2(leftOut))
    return fail2(input);
  const rightOut = right(leftOut.success);
  if (isFailure2(rightOut))
    return fail2(input);
  return rightOut;
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Scheduler.js
var Scheduler = /* @__PURE__ */ Reference("effect/Scheduler", {
  defaultValue: () => new MixedScheduler
});
var setImmediate = "setImmediate" in globalThis ? (f) => {
  const timer = globalThis.setImmediate(f);
  return () => globalThis.clearImmediate(timer);
} : (f) => {
  const timer = setTimeout(f, 0);
  return () => clearTimeout(timer);
};

class PriorityBuckets {
  buckets = [];
  scheduleTask(task, priority) {
    const buckets = this.buckets;
    const len = buckets.length;
    let bucket;
    let index = 0;
    for (;index < len; index++) {
      if (buckets[index][0] > priority)
        break;
      bucket = buckets[index];
    }
    if (bucket && bucket[0] === priority) {
      bucket[1].push(task);
    } else if (index === len) {
      buckets.push([priority, [task]]);
    } else {
      buckets.splice(index, 0, [priority, [task]]);
    }
  }
  drain() {
    const buckets = this.buckets;
    this.buckets = [];
    return buckets;
  }
}

class MixedScheduler {
  executionMode;
  setImmediate;
  constructor(executionMode = "async", setImmediateFn = setImmediate) {
    this.executionMode = executionMode;
    this.setImmediate = setImmediateFn;
  }
  shouldYield(fiber) {
    return fiber.currentOpCount >= fiber.maxOpsBeforeYield;
  }
  makeDispatcher() {
    return new MixedSchedulerDispatcher(this.setImmediate);
  }
}

class MixedSchedulerDispatcher {
  tasks = /* @__PURE__ */ new PriorityBuckets;
  running = undefined;
  setImmediate;
  constructor(setImmediateFn = setImmediate) {
    this.setImmediate = setImmediateFn;
  }
  scheduleTask(task, priority) {
    this.tasks.scheduleTask(task, priority);
    if (this.running === undefined) {
      this.running = this.setImmediate(this.afterScheduled);
    }
  }
  afterScheduled = () => {
    this.running = undefined;
    this.runTasks();
  };
  runTasks() {
    const buckets = this.tasks.drain();
    for (let i = 0;i < buckets.length; i++) {
      const toRun = buckets[i][1];
      for (let j = 0;j < toRun.length; j++) {
        toRun[j]();
      }
    }
  }
  flush() {
    while (this.tasks.buckets.length > 0) {
      if (this.running !== undefined) {
        this.running();
        this.running = undefined;
      }
      this.runTasks();
    }
  }
}
var MaxOpsBeforeYield = /* @__PURE__ */ Reference("effect/Scheduler/MaxOpsBeforeYield", {
  defaultValue: () => 2048
});
var PreventSchedulerYield = /* @__PURE__ */ Reference("effect/Scheduler/PreventSchedulerYield", {
  defaultValue: () => false
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Tracer.js
var ParentSpanKey = "effect/Tracer/ParentSpan";

class ParentSpan extends (/* @__PURE__ */ Service()(ParentSpanKey)) {
}
var make5 = (options) => options;
var DisablePropagation = /* @__PURE__ */ Reference("effect/Tracer/DisablePropagation", {
  defaultValue: constFalse
});
var CurrentTraceLevel = /* @__PURE__ */ Reference("effect/Tracer/CurrentTraceLevel", {
  defaultValue: () => "Info"
});
var MinimumTraceLevel = /* @__PURE__ */ Reference("effect/Tracer/MinimumTraceLevel", {
  defaultValue: () => "All"
});
var TracerKey = "effect/Tracer";
var Tracer = /* @__PURE__ */ Reference(TracerKey, {
  defaultValue: () => make5({
    span: (options) => new NativeSpan(options)
  })
});

class NativeSpan {
  _tag = "Span";
  spanId;
  traceId = "native";
  sampled;
  name;
  parent;
  annotations;
  links;
  startTime;
  kind;
  status;
  attributes;
  events = [];
  constructor(options) {
    this.name = options.name;
    this.parent = options.parent;
    this.annotations = options.annotations;
    this.links = options.links;
    this.startTime = options.startTime;
    this.kind = options.kind;
    this.sampled = options.sampled;
    this.status = {
      _tag: "Started",
      startTime: options.startTime
    };
    this.attributes = new Map;
    this.traceId = getOrUndefined(options.parent)?.traceId ?? randomHexString(32);
    this.spanId = randomHexString(16);
  }
  end(endTime, exit) {
    this.status = {
      _tag: "Ended",
      endTime,
      exit,
      startTime: this.status.startTime
    };
  }
  attribute(key, value) {
    this.attributes.set(key, value);
  }
  event(name, startTime, attributes) {
    this.events.push([name, startTime, attributes ?? {}]);
  }
  addLinks(links) {
    this.links.push(...links);
  }
}
var randomHexString = /* @__PURE__ */ function() {
  const characters = "abcdef0123456789";
  const charactersLength = characters.length;
  return function(length) {
    let result = "";
    for (let i = 0;i < length; i++) {
      result += characters.charAt(Math.floor(Math.random() * charactersLength));
    }
    return result;
  };
}();

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/metric.js
var FiberRuntimeMetricsKey = "effect/observability/Metric/FiberRuntimeMetricsKey";

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/references.js
var CurrentConcurrency = /* @__PURE__ */ Reference("effect/References/CurrentConcurrency", {
  defaultValue: () => "unbounded"
});
var CurrentErrorReporters = /* @__PURE__ */ Reference("effect/ErrorReporter/CurrentErrorReporters", {
  defaultValue: () => new Set
});
var CurrentStackFrame = /* @__PURE__ */ Reference("effect/References/CurrentStackFrame", {
  defaultValue: constUndefined
});
var TracerEnabled = /* @__PURE__ */ Reference("effect/References/TracerEnabled", {
  defaultValue: constTrue
});
var TracerTimingEnabled = /* @__PURE__ */ Reference("effect/References/TracerTimingEnabled", {
  defaultValue: constTrue
});
var TracerSpanAnnotations = /* @__PURE__ */ Reference("effect/References/TracerSpanAnnotations", {
  defaultValue: () => ({})
});
var TracerSpanLinks = /* @__PURE__ */ Reference("effect/References/TracerSpanLinks", {
  defaultValue: () => []
});
var CurrentLogAnnotations = /* @__PURE__ */ Reference("effect/References/CurrentLogAnnotations", {
  defaultValue: () => ({})
});
var CurrentLogLevel = /* @__PURE__ */ Reference("effect/References/CurrentLogLevel", {
  defaultValue: () => "Info"
});
var MinimumLogLevel = /* @__PURE__ */ Reference("effect/References/MinimumLogLevel", {
  defaultValue: () => "Info"
});
var CurrentLogSpans = /* @__PURE__ */ Reference("effect/References/CurrentLogSpans", {
  defaultValue: () => []
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/tracer.js
var addSpanStackTrace = (options) => {
  if (options?.captureStackTrace === false) {
    return options;
  } else if (options?.captureStackTrace !== undefined && typeof options.captureStackTrace !== "boolean") {
    return options;
  }
  const limit = Error.stackTraceLimit;
  Error.stackTraceLimit = 3;
  const traceError = new Error;
  Error.stackTraceLimit = limit;
  return {
    ...options,
    captureStackTrace: spanCleaner(() => traceError.stack)
  };
};
var makeStackCleaner = (line) => (stack) => {
  let cache;
  return () => {
    if (cache !== undefined)
      return cache;
    const trace = stack();
    if (!trace)
      return;
    const lines = trace.split(`
`);
    if (lines[line] !== undefined) {
      cache = lines[line].trim();
      return cache;
    }
  };
};
var spanCleaner = /* @__PURE__ */ makeStackCleaner(3);

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/version.js
var version = "dev";

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/effect.js
class Interrupt extends ReasonBase {
  fiberId;
  constructor(fiberId, annotations = constEmptyAnnotations) {
    super("Interrupt", annotations, "Interrupted");
    this.fiberId = fiberId;
  }
  toString() {
    return `Interrupt(${this.fiberId})`;
  }
  toJSON() {
    return {
      _tag: "Interrupt",
      fiberId: this.fiberId
    };
  }
  [symbol2](that) {
    return isInterruptReason(that) && this.fiberId === that.fiberId && this.annotations === that.annotations;
  }
  [symbol]() {
    return combine(string(`${this._tag}:${this.fiberId}`))(random(this.annotations));
  }
}
var causeInterrupt = (fiberId) => new CauseImpl([new Interrupt(fiberId)]);
var findFail = (self) => {
  const reason = self.reasons.find(isFailReason);
  return reason ? succeed2(reason) : fail2(self);
};
var findError = (self) => {
  for (let i = 0;i < self.reasons.length; i++) {
    const reason = self.reasons[i];
    if (reason._tag === "Fail") {
      return succeed2(reason.error);
    }
  }
  return fail2(self);
};
var hasDies = (self) => self.reasons.some(isDieReason);
var findDefect = (self) => {
  const reason = self.reasons.find(isDieReason);
  return reason ? succeed2(reason.defect) : fail2(self);
};
var hasInterrupts = (self) => self.reasons.some(isInterruptReason);
var causeFilterInterruptors = (self) => {
  let interruptors;
  for (let i = 0;i < self.reasons.length; i++) {
    const f = self.reasons[i];
    if (f._tag !== "Interrupt")
      continue;
    interruptors ??= new Set;
    if (f.fiberId !== undefined) {
      interruptors.add(f.fiberId);
    }
  }
  return interruptors ? succeed2(interruptors) : fail2(self);
};
var causeCombine = /* @__PURE__ */ dual(2, (self, that) => {
  if (self.reasons.length === 0) {
    return that;
  } else if (that.reasons.length === 0) {
    return self;
  }
  const newCause = new CauseImpl(union(self.reasons, that.reasons));
  return equals(self, newCause) ? self : newCause;
});
var causePartition = (self) => {
  const obj = {
    Fail: [],
    Die: [],
    Interrupt: []
  };
  for (let i = 0;i < self.reasons.length; i++) {
    obj[self.reasons[i]._tag].push(self.reasons[i]);
  }
  return obj;
};
var causeSquash = (self) => {
  const partitioned = causePartition(self);
  if (partitioned.Fail.length > 0) {
    return partitioned.Fail[0].error;
  } else if (partitioned.Die.length > 0) {
    return partitioned.Die[0].defect;
  } else if (partitioned.Interrupt.length > 0) {
    return new globalThis.Error("All fibers interrupted without error");
  }
  return new globalThis.Error("Empty cause");
};
var causePrettyErrors = (self) => {
  const errors = [];
  const interrupts = [];
  if (self.reasons.length === 0)
    return errors;
  const prevStackLimit = Error.stackTraceLimit;
  Error.stackTraceLimit = 1;
  for (const failure of self.reasons) {
    if (failure._tag === "Interrupt") {
      interrupts.push(failure);
      continue;
    }
    errors.push(causePrettyError(failure._tag === "Die" ? failure.defect : failure.error, failure.annotations));
  }
  if (errors.length === 0) {
    const cause = new Error("The fiber was interrupted by:");
    cause.name = "InterruptCause";
    cause.stack = interruptCauseStack(cause, interrupts);
    const error = new globalThis.Error("All fibers interrupted without error", {
      cause
    });
    error.name = "InterruptError";
    error.stack = `${error.name}: ${error.message}`;
    errors.push(causePrettyError(error, interrupts[0].annotations));
  }
  Error.stackTraceLimit = prevStackLimit;
  return errors;
};
var causePrettyError = (original, annotations) => {
  const kind = typeof original;
  let error;
  if (original && kind === "object") {
    error = new globalThis.Error(causePrettyMessage(original), {
      cause: original.cause ? causePrettyError(original.cause) : undefined
    });
    if (typeof original.name === "string") {
      error.name = original.name;
    }
    if (typeof original.stack === "string") {
      error.stack = cleanErrorStack(original.stack, error, annotations);
    } else {
      const stack = `${error.name}: ${error.message}`;
      error.stack = annotations ? addStackAnnotations(stack, annotations) : stack;
    }
    for (const key of Object.keys(original)) {
      if (!(key in error)) {
        error[key] = original[key];
      }
    }
  } else {
    error = new globalThis.Error(!original ? `Unknown error: ${original}` : kind === "string" ? original : formatJson(original));
  }
  return error;
};
var causePrettyMessage = (u) => {
  if (typeof u.message === "string") {
    return u.message;
  } else if (typeof u.toString === "function" && u.toString !== Object.prototype.toString && u.toString !== Array.prototype.toString) {
    try {
      return u.toString();
    } catch {}
  }
  return formatJson(u);
};
var locationRegExp = /\((.*)\)/g;
var cleanErrorStack = (stack, error, annotations) => {
  const message = `${error.name}: ${error.message}`;
  const lines = (stack.startsWith(message) ? stack.slice(message.length) : stack).split(`
`);
  const out = [message];
  for (let i = 1;i < lines.length; i++) {
    if (/(?:Generator\.next|~effect\/Effect)/.test(lines[i])) {
      break;
    }
    out.push(lines[i]);
  }
  return annotations ? addStackAnnotations(out.join(`
`), annotations) : out.join(`
`);
};
var addStackAnnotations = (stack, annotations) => {
  const frame = annotations?.get(StackTraceKey.key);
  if (frame) {
    stack = `${stack}
${currentStackTrace(frame)}`;
  }
  return stack;
};
var interruptCauseStack = (error, interrupts) => {
  const out = [`${error.name}: ${error.message}`];
  for (const current of interrupts) {
    const fiberId = current.fiberId !== undefined ? `#${current.fiberId}` : "unknown";
    const frame = current.annotations.get(InterruptorStackTrace.key);
    out.push(`    at fiber (${fiberId})`);
    if (frame)
      out.push(currentStackTrace(frame));
  }
  return out.join(`
`);
};
var currentStackTrace = (frame) => {
  const out = [];
  let current = frame;
  let i = 0;
  while (current && i < 10) {
    const stack = current.stack();
    if (stack) {
      const locationMatchAll = stack.matchAll(locationRegExp);
      let match4 = false;
      for (const [, location] of locationMatchAll) {
        match4 = true;
        out.push(`    at ${current.name} (${location})`);
      }
      if (!match4) {
        out.push(`    at ${current.name} (${stack.replace(/^at /, "")})`);
      }
    } else {
      out.push(`    at ${current.name}`);
    }
    current = current.parent;
    i++;
  }
  return out.join(`
`);
};
var causePretty = (cause) => causePrettyErrors(cause).map((e) => e.cause ? `${e.stack} {
${renderErrorCause(e.cause, "  ")}
}` : e.stack).join(`
`);
var renderErrorCause = (cause, prefix) => {
  const lines = cause.stack.split(`
`);
  let stack = `${prefix}[cause]: ${lines[0]}`;
  for (let i = 1, len = lines.length;i < len; i++) {
    stack += `
${prefix}${lines[i]}`;
  }
  if (cause.cause) {
    stack += ` {
${renderErrorCause(cause.cause, `${prefix}  `)}
${prefix}}`;
  }
  return stack;
};
var FiberTypeId = `~effect/Fiber/${version}`;
var fiberVariance = {
  _A: identity,
  _E: identity
};
var fiberIdStore = {
  id: 0
};
var getCurrentFiber = () => globalThis[currentFiberTypeId];

class FiberImpl {
  constructor(context, interruptible = true) {
    this[FiberTypeId] = fiberVariance;
    this.setContext(context);
    this.id = ++fiberIdStore.id;
    this.currentOpCount = 0;
    this.currentLoopCount = 0;
    this.interruptible = interruptible;
    this._stack = [];
    this._observers = [];
    this._exit = undefined;
    this._children = undefined;
    this._interruptedCause = undefined;
    this._yielded = undefined;
  }
  [FiberTypeId];
  id;
  interruptible;
  currentOpCount;
  currentLoopCount;
  _stack;
  _observers;
  _exit;
  _currentExit;
  _children;
  _interruptedCause;
  _yielded;
  context;
  currentScheduler;
  currentTracerContext;
  currentSpan;
  currentLogLevel;
  minimumLogLevel;
  currentStackFrame;
  runtimeMetrics;
  maxOpsBeforeYield;
  currentPreventYield;
  _dispatcher = undefined;
  get currentDispatcher() {
    return this._dispatcher ??= this.currentScheduler.makeDispatcher();
  }
  getRef(ref) {
    return getReferenceUnsafe(this.context, ref);
  }
  addObserver(cb) {
    if (this._exit) {
      cb(this._exit);
      return constVoid;
    }
    this._observers.push(cb);
    return () => {
      const index = this._observers.indexOf(cb);
      if (index >= 0) {
        this._observers.splice(index, 1);
      }
    };
  }
  interruptUnsafe(fiberId, annotations) {
    if (this._exit) {
      return;
    }
    let cause = causeInterrupt(fiberId);
    if (this.currentStackFrame) {
      cause = causeAnnotate(cause, make3(StackTraceKey, this.currentStackFrame));
    }
    if (annotations) {
      cause = causeAnnotate(cause, annotations);
    }
    this._interruptedCause = this._interruptedCause ? causeCombine(this._interruptedCause, cause) : cause;
    if (this.interruptible) {
      this.evaluate(failCause(this._interruptedCause));
    }
  }
  pollUnsafe() {
    return this._exit;
  }
  evaluate(effect) {
    this.runtimeMetrics?.recordFiberStart(this.context);
    if (this._exit) {
      return;
    } else if (this._yielded !== undefined) {
      const yielded = this._yielded;
      this._yielded = undefined;
      yielded();
    }
    const exit = this.runLoop(effect);
    if (exit === Yield) {
      return;
    }
    const interruptChildren = fiberMiddleware.interruptChildren && fiberMiddleware.interruptChildren(this);
    if (interruptChildren !== undefined) {
      return this.evaluate(flatMap(interruptChildren, () => exit));
    }
    this._exit = exit;
    this.runtimeMetrics?.recordFiberEnd(this.context, this._exit);
    for (let i = 0;i < this._observers.length; i++) {
      this._observers[i](exit);
    }
    this._observers.length = 0;
  }
  runLoop(effect) {
    const prevFiber = globalThis[currentFiberTypeId];
    globalThis[currentFiberTypeId] = this;
    let yielding = false;
    let current = effect;
    this.currentOpCount = 0;
    const currentLoop = ++this.currentLoopCount;
    try {
      while (true) {
        this.currentOpCount++;
        if (!yielding && !this.currentPreventYield && this.currentScheduler.shouldYield(this)) {
          yielding = true;
          const prev = current;
          current = flatMap(yieldNow, () => prev);
        }
        current = this.currentTracerContext ? this.currentTracerContext(current, this) : current[evaluate](this);
        if (currentLoop !== this.currentLoopCount) {
          return Yield;
        } else if (current === Yield) {
          const yielded = this._yielded;
          if (ExitTypeId in yielded) {
            this._yielded = undefined;
            return yielded;
          }
          return Yield;
        }
      }
    } catch (error) {
      if (!hasProperty(current, evaluate)) {
        return exitDie(`Fiber.runLoop: Not a valid effect: ${String(current)}`);
      }
      return this.runLoop(exitDie(error));
    } finally {
      globalThis[currentFiberTypeId] = prevFiber;
    }
  }
  getCont(symbol3) {
    while (true) {
      const op = this._stack.pop();
      if (!op)
        return;
      const cont = op[contAll] && op[contAll](this);
      if (cont) {
        cont[symbol3] = cont;
        return cont;
      }
      if (op[symbol3])
        return op;
    }
  }
  yieldWith(value) {
    this._yielded = value;
    return Yield;
  }
  children() {
    return this._children ??= new Set;
  }
  pipe() {
    return pipeArguments(this, arguments);
  }
  setContext(context) {
    this.context = context;
    const scheduler = this.getRef(Scheduler);
    if (scheduler !== this.currentScheduler) {
      this.currentScheduler = scheduler;
      this._dispatcher = undefined;
    }
    this.currentSpan = context.mapUnsafe.get(ParentSpanKey);
    this.currentLogLevel = this.getRef(CurrentLogLevel);
    this.minimumLogLevel = this.getRef(MinimumLogLevel);
    this.currentStackFrame = context.mapUnsafe.get(CurrentStackFrame.key);
    this.maxOpsBeforeYield = this.getRef(MaxOpsBeforeYield);
    this.currentPreventYield = this.getRef(PreventSchedulerYield);
    this.runtimeMetrics = context.mapUnsafe.get(FiberRuntimeMetricsKey);
    const currentTracer = context.mapUnsafe.get(TracerKey);
    this.currentTracerContext = currentTracer ? currentTracer["context"] : undefined;
  }
  get currentSpanLocal() {
    return this.currentSpan?._tag === "Span" ? this.currentSpan : undefined;
  }
}
var fiberMiddleware = {
  interruptChildren: undefined
};
var fiberStackAnnotations = (fiber) => {
  if (!fiber.currentStackFrame)
    return;
  const annotations = new Map;
  annotations.set(StackTraceKey.key, fiber.currentStackFrame);
  return makeUnsafe(annotations);
};
var fiberInterruptChildren = (fiber) => {
  if (fiber._children === undefined || fiber._children.size === 0) {
    return;
  }
  return fiberInterruptAll(fiber._children);
};
var fiberAwait = (self) => {
  const impl = self;
  if (impl._exit)
    return succeed3(impl._exit);
  return callback((resume) => {
    if (impl._exit)
      return resume(succeed3(impl._exit));
    return sync(self.addObserver((exit) => resume(succeed3(exit))));
  });
};
var fiberAwaitAll = (self) => callback((resume) => {
  const iter = self[Symbol.iterator]();
  const exits = [];
  let cancel = undefined;
  function loop() {
    let result = iter.next();
    while (!result.done) {
      if (result.value._exit) {
        exits.push(result.value._exit);
        result = iter.next();
        continue;
      }
      cancel = result.value.addObserver((exit) => {
        exits.push(exit);
        loop();
      });
      return;
    }
    resume(succeed3(exits));
  }
  loop();
  return sync(() => cancel?.());
});
var fiberInterrupt = (self) => withFiber((fiber) => fiberInterruptAs(self, fiber.id));
var fiberInterruptAs = /* @__PURE__ */ dual((args2) => hasProperty(args2[0], FiberTypeId), (self, fiberId, annotations) => withFiber((parent) => {
  let ann = fiberStackAnnotations(parent);
  ann = ann && annotations ? merge(ann, annotations) : ann ?? annotations;
  self.interruptUnsafe(fiberId, ann);
  return asVoid(fiberAwait(self));
}));
var fiberInterruptAll = (fibers) => withFiber((parent) => {
  const annotations = fiberStackAnnotations(parent);
  for (const fiber of fibers) {
    fiber.interruptUnsafe(parent.id, annotations);
  }
  return asVoid(fiberAwaitAll(fibers));
});
var succeed3 = exitSucceed;
var failCause = exitFailCause;
var fail3 = exitFail;
var sync = /* @__PURE__ */ makePrimitive({
  op: "Sync",
  [evaluate](fiber) {
    const value = this[args]();
    const cont = fiber.getCont(contA);
    return cont ? cont[contA](value, fiber) : fiber.yieldWith(exitSucceed(value));
  }
});
var suspend = /* @__PURE__ */ makePrimitive({
  op: "Suspend",
  [evaluate](_fiber) {
    return this[args]();
  }
});
var fromYieldable = (yieldable) => yieldable.asEffect();
var fromOption2 = fromYieldable;
var fromResult = fromYieldable;
var fromNullishOr = (value) => value == null ? fail3(new NoSuchElementError) : succeed3(value);
var yieldNowWith = /* @__PURE__ */ makePrimitive({
  op: "Yield",
  [evaluate](fiber) {
    let resumed = false;
    fiber.currentDispatcher.scheduleTask(() => {
      if (resumed)
        return;
      fiber.evaluate(exitVoid);
    }, this[args] ?? 0);
    return fiber.yieldWith(() => {
      resumed = true;
    });
  }
});
var yieldNow = /* @__PURE__ */ yieldNowWith(0);
var succeedSome = (a) => succeed3(some2(a));
var succeedNone = /* @__PURE__ */ succeed3(/* @__PURE__ */ none2());
var failCauseSync = (evaluate2) => suspend(() => failCause(internalCall(evaluate2)));
var die = (defect) => exitDie(defect);
var failSync = (error) => suspend(() => fail3(internalCall(error)));
var void_ = /* @__PURE__ */ succeed3(undefined);
var try_ = (options) => suspend(() => {
  try {
    return succeed3(internalCall(options.try));
  } catch (err) {
    return fail3(internalCall(() => options.catch(err)));
  }
});
var promise = (evaluate2) => callbackOptions(function(resume, signal) {
  internalCall(() => evaluate2(signal)).then((a) => resume(succeed3(a)), (e) => resume(die(e)));
}, evaluate2.length !== 0);
var tryPromise = (options) => {
  const f = typeof options === "function" ? options : options.try;
  const catcher = typeof options === "function" ? (cause) => new UnknownError(cause, "An error occurred in Effect.tryPromise") : options.catch;
  return callbackOptions(function(resume, signal) {
    try {
      internalCall(() => f(signal)).then((a) => resume(succeed3(a)), (e) => resume(fail3(internalCall(() => catcher(e)))));
    } catch (err) {
      resume(fail3(internalCall(() => catcher(err))));
    }
  }, eval.length !== 0);
};
var withFiberId = (f) => withFiber((fiber) => f(fiber.id));
var fiber = /* @__PURE__ */ withFiber(succeed3);
var fiberId = /* @__PURE__ */ withFiberId(succeed3);
var callbackOptions = /* @__PURE__ */ makePrimitive({
  op: "Async",
  single: false,
  [evaluate](fiber2) {
    const register = internalCall(() => this[args][0].bind(fiber2.currentScheduler));
    let resumed = false;
    let yielded = false;
    const controller = this[args][1] ? new AbortController : undefined;
    const onCancel = register((effect) => {
      if (resumed)
        return;
      resumed = true;
      if (yielded) {
        fiber2.evaluate(effect);
      } else {
        yielded = effect;
      }
    }, controller?.signal);
    if (yielded !== false)
      return yielded;
    yielded = true;
    fiber2._yielded = () => {
      resumed = true;
    };
    if (controller === undefined && onCancel === undefined) {
      return Yield;
    }
    fiber2._stack.push(asyncFinalizer(() => {
      resumed = true;
      controller?.abort();
      return onCancel ?? exitVoid;
    }));
    return Yield;
  }
});
var asyncFinalizer = /* @__PURE__ */ makePrimitive({
  op: "AsyncFinalizer",
  [contAll](fiber2) {
    if (fiber2.interruptible) {
      fiber2.interruptible = false;
      fiber2._stack.push(setInterruptibleTrue);
    }
  },
  [contE](cause, _fiber) {
    return hasInterrupts(cause) ? flatMap(this[args](), () => failCause(cause)) : failCause(cause);
  }
});
var callback = (register) => callbackOptions(register, register.length >= 2);
var never = /* @__PURE__ */ callback(constVoid);
var gen = (...args2) => suspend(() => fromIteratorUnsafe(args2.length === 1 ? args2[0]() : args2[1].call(args2[0].self)));
var fnUntraced = (body, ...pipeables) => {
  const fn = pipeables.length === 0 ? function() {
    return suspend(() => fromIteratorUnsafe(body.apply(this, arguments)));
  } : function() {
    let effect = suspend(() => fromIteratorUnsafe(body.apply(this, arguments)));
    for (let i = 0;i < pipeables.length; i++) {
      effect = pipeables[i](effect, ...arguments);
    }
    return effect;
  };
  return defineFunctionLength(body.length, fn);
};
var defineFunctionLength = (length, fn) => Object.defineProperty(fn, "length", {
  value: length,
  configurable: true
});
var fnStackCleaner = /* @__PURE__ */ makeStackCleaner(2);
var fn = function() {
  const nameFirst = typeof arguments[0] === "string";
  const name = nameFirst ? arguments[0] : "Effect.fn";
  const spanOptions = nameFirst ? arguments[1] : undefined;
  const prevLimit = globalThis.Error.stackTraceLimit;
  globalThis.Error.stackTraceLimit = 2;
  const defError = new globalThis.Error;
  globalThis.Error.stackTraceLimit = prevLimit;
  if (nameFirst) {
    return (body, ...pipeables) => makeFn(name, body, defError, pipeables, nameFirst, spanOptions);
  }
  return makeFn(name, arguments[0], defError, Array.prototype.slice.call(arguments, 1), nameFirst, spanOptions);
};
var makeFn = (name, bodyOrOptions, defError, pipeables, addSpan, spanOptions) => {
  const body = typeof bodyOrOptions === "function" ? bodyOrOptions : pipeables.pop().bind(bodyOrOptions.self);
  return defineFunctionLength(body.length, function(...args2) {
    let result = suspend(() => {
      const iter = body.apply(this, arguments);
      return isEffect(iter) ? iter : fromIteratorUnsafe(iter);
    });
    for (let i = 0;i < pipeables.length; i++) {
      result = pipeables[i](result, ...args2);
    }
    if (!isEffect(result)) {
      return result;
    }
    const prevLimit = globalThis.Error.stackTraceLimit;
    globalThis.Error.stackTraceLimit = 2;
    const callError = new globalThis.Error;
    globalThis.Error.stackTraceLimit = prevLimit;
    return updateService(addSpan ? useSpan(name, spanOptions, (span) => provideParentSpan(result, span)) : result, CurrentStackFrame, (prev) => ({
      name,
      stack: fnStackCleaner(() => callError.stack),
      parent: {
        name: `${name} (definition)`,
        stack: fnStackCleaner(() => defError.stack),
        parent: prev
      }
    }));
  });
};
var fnUntracedEager = (body, ...pipeables) => defineFunctionLength(body.length, pipeables.length === 0 ? function() {
  return fromIteratorEagerUnsafe(() => body.apply(this, arguments));
} : function() {
  let effect = fromIteratorEagerUnsafe(() => body.apply(this, arguments));
  for (const pipeable of pipeables) {
    effect = pipeable(effect);
  }
  return effect;
});
var fromIteratorEagerUnsafe = (evaluate2) => {
  try {
    const iterator = evaluate2();
    let value = undefined;
    while (true) {
      const state = iterator.next(value);
      if (state.done) {
        return succeed3(state.value);
      }
      const yieldable = state.value;
      const effect = yieldable.asEffect();
      const primitive = effect;
      if (primitive && primitive._tag === "Success") {
        value = primitive.value;
        continue;
      } else if (primitive && primitive._tag === "Failure") {
        return effect;
      } else {
        let isFirstExecution = true;
        return suspend(() => {
          if (isFirstExecution) {
            isFirstExecution = false;
            return flatMap(effect, (value2) => fromIteratorUnsafe(iterator, value2));
          } else {
            return suspend(() => fromIteratorUnsafe(evaluate2()));
          }
        });
      }
    }
  } catch (error) {
    return die(error);
  }
};
var fromIteratorUnsafe = /* @__PURE__ */ makePrimitive({
  op: "Iterator",
  single: false,
  [contA](value, fiber2) {
    const iter = this[args][0];
    while (true) {
      const state = iter.next(value);
      if (state.done)
        return succeed3(state.value);
      const eff = state.value.asEffect();
      if (!effectIsExit(eff)) {
        fiber2._stack.push(this);
        return eff;
      } else if (eff._tag === "Failure") {
        return eff;
      }
      value = eff.value;
    }
  },
  [evaluate](fiber2) {
    return this[contA](this[args][1], fiber2);
  }
});
var as = /* @__PURE__ */ dual(2, (self, value) => {
  const b = succeed3(value);
  return flatMap(self, (_) => b);
});
var asSome = (self) => map4(self, some2);
var flip = (self) => matchEffect(self, {
  onFailure: succeed3,
  onSuccess: fail3
});
var andThen = /* @__PURE__ */ dual(2, (self, f) => flatMap(self, (a) => isEffect(f) ? f : internalCall(() => f(a))));
var tap = /* @__PURE__ */ dual(2, (self, f) => flatMap(self, (a) => as(isEffect(f) ? f : internalCall(() => f(a)), a)));
var asVoid = (self) => flatMap(self, (_) => exitVoid);
var sandbox = (self) => catchCause(self, fail3);
var raceAll = (all, options) => withFiber((parent) => callback((resume) => {
  const effects = fromIterable(all);
  const len = effects.length;
  let doneCount = 0;
  let done2 = false;
  const fibers = new Set;
  const failures = [];
  const onExit = (exit, fiber2, i) => {
    doneCount++;
    if (exit._tag === "Failure") {
      failures.push(...exit.cause.reasons);
      if (doneCount >= len) {
        resume(failCause(causeFromReasons(failures)));
      }
      return;
    }
    const isWinner = !done2;
    done2 = true;
    resume(fibers.size === 0 ? exit : flatMap(uninterruptible(fiberInterruptAll(fibers)), () => exit));
    if (isWinner && options?.onWinner) {
      options.onWinner({
        fiber: fiber2,
        index: i,
        parentFiber: parent
      });
    }
  };
  for (let i = 0;i < len; i++) {
    const fiber2 = forkUnsafe(parent, effects[i], true, true, false);
    fibers.add(fiber2);
    fiber2.addObserver((exit) => {
      fibers.delete(fiber2);
      onExit(exit, fiber2, i);
    });
    if (done2)
      break;
  }
  return fiberInterruptAll(fibers);
}));
var raceAllFirst = (all, options) => withFiber((parent) => callback((resume) => {
  let done2 = false;
  const fibers = new Set;
  const onExit = (exit) => {
    done2 = true;
    resume(fibers.size === 0 ? exit : flatMap(uninterruptible(fiberInterruptAll(fibers)), () => exit));
  };
  let i = 0;
  for (const effect of all) {
    if (done2)
      break;
    const index = i++;
    const fiber2 = forkUnsafe(parent, effect, true, true, false);
    fibers.add(fiber2);
    fiber2.addObserver((exit) => {
      fibers.delete(fiber2);
      const isWinner = !done2;
      onExit(exit);
      if (isWinner && options?.onWinner) {
        options.onWinner({
          fiber: fiber2,
          index,
          parentFiber: parent
        });
      }
    });
  }
  return fiberInterruptAll(fibers);
}));
var race = /* @__PURE__ */ dual((args2) => isEffect(args2[1]), (self, that, options) => raceAll([self, that], options));
var raceFirst = /* @__PURE__ */ dual((args2) => isEffect(args2[1]), (self, that, options) => raceAllFirst([self, that], options));
var flatMap = /* @__PURE__ */ dual(2, (self, f) => {
  const onSuccess = Object.create(OnSuccessProto);
  onSuccess[args] = self;
  onSuccess[contA] = f.length !== 1 ? (a) => f(a) : f;
  return onSuccess;
});
var OnSuccessProto = /* @__PURE__ */ makePrimitiveProto({
  op: "OnSuccess",
  [evaluate](fiber2) {
    fiber2._stack.push(this);
    return this[args];
  }
});
var matchCauseEffectEager = /* @__PURE__ */ dual(2, (self, options) => {
  if (effectIsExit(self)) {
    return self._tag === "Success" ? options.onSuccess(self.value) : options.onFailure(self.cause);
  }
  return matchCauseEffect(self, options);
});
var effectIsExit = (effect) => (ExitTypeId in effect);
var flatMapEager = /* @__PURE__ */ dual(2, (self, f) => {
  if (effectIsExit(self)) {
    return self._tag === "Success" ? f(self.value) : self;
  }
  return flatMap(self, f);
});
var flatten = (self) => flatMap(self, identity);
var map4 = /* @__PURE__ */ dual(2, (self, f) => flatMap(self, (a) => succeed3(internalCall(() => f(a)))));
var mapEager = /* @__PURE__ */ dual(2, (self, f) => effectIsExit(self) ? exitMap(self, f) : map4(self, f));
var mapErrorEager = /* @__PURE__ */ dual(2, (self, f) => effectIsExit(self) ? exitMapError(self, f) : mapError2(self, f));
var mapBothEager = /* @__PURE__ */ dual(2, (self, options) => effectIsExit(self) ? exitMapBoth(self, options) : mapBoth(self, options));
var catchEager = /* @__PURE__ */ dual(2, (self, f) => {
  if (effectIsExit(self)) {
    if (self._tag === "Success")
      return self;
    const error = findError(self.cause);
    if (isFailure2(error))
      return self;
    return f(error.success);
  }
  return catch_(self, f);
});
var exitIsSuccess = (self) => self._tag === "Success";
var exitFilterCause = (self) => self._tag === "Failure" ? succeed2(self.cause) : fail2(self);
var exitVoid = /* @__PURE__ */ exitSucceed(undefined);
var exitMap = /* @__PURE__ */ dual(2, (self, f) => self._tag === "Success" ? exitSucceed(f(self.value)) : self);
var exitMapError = /* @__PURE__ */ dual(2, (self, f) => {
  if (self._tag === "Success")
    return self;
  const error = findError(self.cause);
  if (isFailure2(error))
    return self;
  return exitFail(f(error.success));
});
var exitMapBoth = /* @__PURE__ */ dual(2, (self, options) => {
  if (self._tag === "Success")
    return exitSucceed(options.onSuccess(self.value));
  const error = findError(self.cause);
  if (isFailure2(error))
    return self;
  return exitFail(options.onFailure(error.success));
});
var exitAsVoidAll = (exits) => {
  const failures = [];
  for (const exit of exits) {
    if (exit._tag === "Failure") {
      failures.push(...exit.cause.reasons);
    }
  }
  return failures.length === 0 ? exitVoid : exitFailCause(causeFromReasons(failures));
};
var exitGetSuccess = (self) => exitIsSuccess(self) ? some2(self.value) : none2();
var service = fromYieldable;
var serviceOption = (service2) => withFiber((fiber2) => succeed3(getOption(fiber2.context, service2)));
var serviceOptional = (service2) => withFiber((fiber2) => fiber2.context.mapUnsafe.has(service2.key) ? succeed3(getUnsafe2(fiber2.context, service2)) : fail3(new NoSuchElementError));
var updateContext = /* @__PURE__ */ dual(2, (self, f) => withFiber((fiber2) => {
  const prevContext = fiber2.context;
  const nextContext = f(prevContext);
  if (prevContext === nextContext)
    return self;
  fiber2.setContext(nextContext);
  return onExitPrimitive(self, () => {
    fiber2.setContext(prevContext);
    return;
  });
}));
var updateService = /* @__PURE__ */ dual(3, (self, service2, f) => updateContext(self, (s) => {
  const prev = getUnsafe2(s, service2);
  const next = f(prev);
  if (prev === next)
    return s;
  return add(s, service2, next);
}));
var context = () => getContext;
var getContext = /* @__PURE__ */ withFiber((fiber2) => succeed3(fiber2.context));
var contextWith = (f) => withFiber((fiber2) => f(fiber2.context));
var provideContext = /* @__PURE__ */ dual(2, (self, context2) => {
  if (effectIsExit(self))
    return self;
  return updateContext(self, merge(context2));
});
var provideService = function() {
  if (arguments.length === 1) {
    return dual(2, (self, impl) => provideServiceImpl(self, arguments[0], impl));
  }
  return dual(3, (self, service2, impl) => provideServiceImpl(self, service2, impl)).apply(this, arguments);
};
var provideServiceImpl = (self, service2, implementation) => updateContext(self, (s) => {
  const prev = s.mapUnsafe.get(service2.key);
  if (prev === implementation)
    return s;
  return add(s, service2, implementation);
});
var provideServiceEffect = /* @__PURE__ */ dual(3, (self, service2, acquire) => flatMap(acquire, (implementation) => provideService(self, service2, implementation)));
var withConcurrency = /* @__PURE__ */ provideService(CurrentConcurrency);
var zip = /* @__PURE__ */ dual((args2) => isEffect(args2[1]), (self, that, options) => zipWith(self, that, (a, a2) => [a, a2], options));
var zipWith = /* @__PURE__ */ dual((args2) => isEffect(args2[1]), (self, that, f, options) => options?.concurrent ? map4(all([self, that], {
  concurrency: 2
}), ([a, a2]) => internalCall(() => f(a, a2))) : flatMap(self, (a) => map4(that, (a2) => internalCall(() => f(a, a2)))));
var filterOrFail = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, predicate, orFailWith) => filterOrElse(self, predicate, orFailWith ? (a) => fail3(orFailWith(a)) : () => fail3(new NoSuchElementError)));
var when = /* @__PURE__ */ dual(2, (self, condition) => flatMap(condition, (pass) => pass ? asSome(self) : succeedNone));
var replicate = /* @__PURE__ */ dual(2, (self, n) => Array.from({
  length: n
}, () => self));
var replicateEffect = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, n, options) => all(replicate(self, n), options));
var forever = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, options) => whileLoop({
  while: constTrue,
  body: constant(options?.disableYield ? self : flatMap(self, (_) => yieldNow)),
  step: constVoid
}));
var catchCause = /* @__PURE__ */ dual(2, (self, f) => {
  const onFailure = Object.create(OnFailureProto);
  onFailure[args] = self;
  onFailure[contE] = f.length !== 1 ? (cause) => f(cause) : f;
  return onFailure;
});
var OnFailureProto = /* @__PURE__ */ makePrimitiveProto({
  op: "OnFailure",
  [evaluate](fiber2) {
    fiber2._stack.push(this);
    return this[args];
  }
});
var catchCauseIf = /* @__PURE__ */ dual(3, (self, predicate, f) => catchCause(self, (cause) => {
  if (!predicate(cause)) {
    return failCause(cause);
  }
  return internalCall(() => f(cause));
}));
var catchCauseFilter = /* @__PURE__ */ dual(3, (self, filter3, f) => catchCause(self, (cause) => {
  const eb = filter3(cause);
  return isFailure2(eb) ? failCause(eb.failure) : internalCall(() => f(eb.success, cause));
}));
var catch_ = /* @__PURE__ */ dual(2, (self, f) => catchCauseFilter(self, findError, (e) => f(e)));
var catchNoSuchElement = (self) => matchEffect(self, {
  onFailure: (error) => isNoSuchElementError(error) ? succeedNone : fail3(error),
  onSuccess: succeedSome
});
var catchDefect = /* @__PURE__ */ dual(2, (self, f) => catchCauseFilter(self, findDefect, f));
var tapCause = /* @__PURE__ */ dual(2, (self, f) => catchCause(self, (cause) => andThen(internalCall(() => f(cause)), failCause(cause))));
var tapCauseIf = /* @__PURE__ */ dual(3, (self, predicate, f) => catchCauseIf(self, predicate, (cause) => andThen(internalCall(() => f(cause)), failCause(cause))));
var tapCauseFilter = /* @__PURE__ */ dual(3, (self, filter3, f) => catchCause(self, (cause) => {
  const result = filter3(cause);
  if (isFailure2(result)) {
    return failCause(cause);
  }
  return andThen(internalCall(() => f(result.success, cause)), failCause(cause));
}));
var tapError = /* @__PURE__ */ dual(2, (self, f) => tapCauseFilter(self, findError, (e) => f(e)));
var tapErrorTag = /* @__PURE__ */ dual(3, (self, k, f) => {
  const predicate = Array.isArray(k) ? (e) => hasProperty(e, "_tag") && k.includes(e._tag) : isTagged(k);
  return tapError(self, (error) => predicate(error) ? f(error) : void_);
});
var tapDefect = /* @__PURE__ */ dual(2, (self, f) => tapCauseFilter(self, findDefect, (_) => f(_)));
var catchIf = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, predicate, f, orElse) => catchCause(self, (cause) => {
  const error = findError(cause);
  if (isFailure2(error))
    return failCause(error.failure);
  if (!predicate(error.success)) {
    return orElse ? internalCall(() => orElse(error.success)) : failCause(cause);
  }
  return internalCall(() => f(error.success));
}));
var catchFilter = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, filter3, f, orElse) => catchCause(self, (cause) => {
  const error = findError(cause);
  if (isFailure2(error))
    return failCause(error.failure);
  const result = filter3(error.success);
  if (isFailure2(result)) {
    return orElse ? internalCall(() => orElse(result.failure)) : failCause(cause);
  }
  return internalCall(() => f(result.success));
}));
var catchTag = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, k, f, orElse) => {
  const pred = Array.isArray(k) ? (e) => hasProperty(e, "_tag") && k.includes(e._tag) : isTagged(k);
  return catchIf(self, pred, f, orElse);
});
var catchTags = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, cases, orElse) => {
  let keys2;
  return catchFilter(self, (e) => {
    keys2 ??= Object.keys(cases);
    return hasProperty(e, "_tag") && isString(e["_tag"]) && keys2.includes(e["_tag"]) ? succeed2(e) : fail2(e);
  }, (e) => internalCall(() => cases[e["_tag"]](e)), orElse);
});
var catchReason = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, errorTag, reasonTag, f, orElse) => catchIf(self, (e) => isTagged(e, errorTag) && hasProperty(e, "reason"), (e) => {
  const reason = e.reason;
  if (isTagged(reason, reasonTag))
    return f(reason, e);
  return orElse ? internalCall(() => orElse(reason, e)) : fail3(e);
}));
var catchReasons = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, errorTag, cases, orElse) => {
  let keys2;
  return catchIf(self, (e) => isTagged(e, errorTag) && hasProperty(e, "reason") && hasProperty(e.reason, "_tag") && isString(e.reason._tag), (e) => {
    const reason = e.reason;
    keys2 ??= Object.keys(cases);
    if (keys2.includes(reason._tag)) {
      return internalCall(() => cases[reason._tag](reason, e));
    }
    return orElse ? internalCall(() => orElse(reason, e)) : fail3(e);
  });
});
var unwrapReason = /* @__PURE__ */ dual(2, (self, errorTag) => catchFilter(self, (e) => {
  if (isTagged(e, errorTag) && hasProperty(e, "reason")) {
    return succeed2(e.reason);
  }
  return fail2(e);
}, fail3));
var mapError2 = /* @__PURE__ */ dual(2, (self, f) => catch_(self, (error) => failSync(() => f(error))));
var mapBoth = /* @__PURE__ */ dual(2, (self, options) => matchEffect(self, {
  onFailure: (e) => failSync(() => options.onFailure(e)),
  onSuccess: (a) => sync(() => options.onSuccess(a))
}));
var orDie = (self) => catch_(self, die);
var orElseSucceed = /* @__PURE__ */ dual(2, (self, f) => catch_(self, (_) => sync(f)));
var eventually = (self) => catch_(self, (_) => flatMap(yieldNow, () => eventually(self)));
var ignore = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, options) => {
  if (!options?.log) {
    return matchEffect(self, {
      onFailure: (_) => void_,
      onSuccess: (_) => void_
    });
  }
  const logEffect = logWithLevel(options.log === true ? undefined : options.log);
  return matchCauseEffect(self, {
    onFailure(cause) {
      const failure = findFail(cause);
      return isFailure2(failure) ? failCause(failure.failure) : options.message === undefined ? logEffect(cause) : logEffect(options.message, cause);
    },
    onSuccess: (_) => void_
  });
});
var ignoreCause = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, options) => {
  if (!options?.log) {
    return matchCauseEffect(self, {
      onFailure: (_) => void_,
      onSuccess: (_) => void_
    });
  }
  const logEffect = logWithLevel(options.log === true ? undefined : options.log);
  return matchCauseEffect(self, {
    onFailure: (cause) => options.message === undefined ? logEffect(cause) : logEffect(options.message, cause),
    onSuccess: (_) => void_
  });
});
var option = (self) => match4(self, {
  onFailure: none2,
  onSuccess: some2
});
var result = (self) => matchEager(self, {
  onFailure: fail2,
  onSuccess: succeed2
});
var matchCauseEffect = /* @__PURE__ */ dual(2, (self, options) => {
  const primitive = Object.create(OnSuccessAndFailureProto);
  primitive[args] = self;
  primitive[contA] = options.onSuccess.length !== 1 ? (a) => options.onSuccess(a) : options.onSuccess;
  primitive[contE] = options.onFailure.length !== 1 ? (cause) => options.onFailure(cause) : options.onFailure;
  return primitive;
});
var OnSuccessAndFailureProto = /* @__PURE__ */ makePrimitiveProto({
  op: "OnSuccessAndFailure",
  [evaluate](fiber2) {
    fiber2._stack.push(this);
    return this[args];
  }
});
var matchCause = /* @__PURE__ */ dual(2, (self, options) => matchCauseEffect(self, {
  onFailure: (cause) => sync(() => options.onFailure(cause)),
  onSuccess: (value) => sync(() => options.onSuccess(value))
}));
var matchEffect = /* @__PURE__ */ dual(2, (self, options) => matchCauseEffect(self, {
  onFailure: (cause) => {
    const fail4 = cause.reasons.find(isFailReason);
    return fail4 ? internalCall(() => options.onFailure(fail4.error)) : failCause(cause);
  },
  onSuccess: options.onSuccess
}));
var match4 = /* @__PURE__ */ dual(2, (self, options) => matchEffect(self, {
  onFailure: (error) => sync(() => options.onFailure(error)),
  onSuccess: (value) => sync(() => options.onSuccess(value))
}));
var matchEager = /* @__PURE__ */ dual(2, (self, options) => {
  if (effectIsExit(self)) {
    if (self._tag === "Success")
      return exitSucceed(options.onSuccess(self.value));
    const error = findError(self.cause);
    if (isFailure2(error))
      return self;
    return exitSucceed(options.onFailure(error.success));
  }
  return match4(self, options);
});
var matchCauseEager = /* @__PURE__ */ dual(2, (self, options) => {
  if (effectIsExit(self)) {
    if (self._tag === "Success")
      return exitSucceed(options.onSuccess(self.value));
    return exitSucceed(options.onFailure(self.cause));
  }
  return matchCause(self, options);
});
var exit = (self) => effectIsExit(self) ? exitSucceed(self) : exitPrimitive(self);
var exitPrimitive = /* @__PURE__ */ makePrimitive({
  op: "Exit",
  [evaluate](fiber2) {
    fiber2._stack.push(this);
    return this[args];
  },
  [contA](value, _, exit2) {
    return succeed3(exit2 ?? exitSucceed(value));
  },
  [contE](cause, _, exit2) {
    return succeed3(exit2 ?? exitFailCause(cause));
  }
});
var isFailure3 = /* @__PURE__ */ matchEager({
  onFailure: () => true,
  onSuccess: () => false
});
var isSuccess3 = /* @__PURE__ */ matchEager({
  onFailure: () => false,
  onSuccess: () => true
});
var delay = /* @__PURE__ */ dual(2, (self, duration) => andThen(sleep(duration), self));
var timeoutOrElse = /* @__PURE__ */ dual(2, (self, options) => raceFirst(self, flatMap(sleep(options.duration), options.orElse)));
var timeout = /* @__PURE__ */ dual(2, (self, duration) => timeoutOrElse(self, {
  duration,
  orElse: () => fail3(new TimeoutError)
}));
var timeoutOption = /* @__PURE__ */ dual(2, (self, duration) => raceFirst(asSome(self), as(sleep(duration), none2())));
var timed = (self) => clockWith((clock) => {
  const start = clock.currentTimeNanosUnsafe();
  return map4(self, (a) => [nanos(clock.currentTimeNanosUnsafe() - start), a]);
});
var ScopeTypeId = "~effect/Scope";
var ScopeCloseableTypeId = "~effect/Scope/Closeable";
var scopeTag = /* @__PURE__ */ Service("effect/Scope");
var scopeClose = (self, exit_) => suspend(() => scopeCloseUnsafe(self, exit_) ?? void_);
var scopeCloseUnsafe = (self, exit_) => {
  if (self.state._tag === "Closed")
    return;
  const closed = {
    _tag: "Closed",
    exit: exit_
  };
  if (self.state._tag === "Empty") {
    self.state = closed;
    return;
  }
  const {
    finalizers
  } = self.state;
  self.state = closed;
  if (finalizers.size === 0) {
    return;
  } else if (finalizers.size === 1) {
    return finalizers.values().next().value(exit_);
  }
  return scopeCloseFinalizers(self, finalizers, exit_);
};
var scopeCloseFinalizers = /* @__PURE__ */ fnUntraced(function* (self, finalizers, exit_) {
  let exits = [];
  const fibers = [];
  const arr = Array.from(finalizers.values());
  const parent = getCurrentFiber();
  for (let i = arr.length - 1;i >= 0; i--) {
    const finalizer = arr[i];
    if (self.strategy === "sequential") {
      exits.push(yield* exit(finalizer(exit_)));
    } else {
      fibers.push(forkUnsafe(parent, finalizer(exit_), true, true, "inherit"));
    }
  }
  if (fibers.length > 0) {
    exits = yield* fiberAwaitAll(fibers);
  }
  return yield* exitAsVoidAll(exits);
});
var scopeForkUnsafe = (scope, finalizerStrategy) => {
  const newScope = scopeMakeUnsafe(finalizerStrategy);
  if (scope.state._tag === "Closed") {
    newScope.state = scope.state;
    return newScope;
  }
  const key = {};
  scopeAddFinalizerUnsafe(scope, key, (exit2) => scopeClose(newScope, exit2));
  scopeAddFinalizerUnsafe(newScope, key, (_) => sync(() => scopeRemoveFinalizerUnsafe(scope, key)));
  return newScope;
};
var scopeAddFinalizerExit = (scope, finalizer) => {
  return suspend(() => {
    if (scope.state._tag === "Closed") {
      return finalizer(scope.state.exit);
    }
    scopeAddFinalizerUnsafe(scope, {}, finalizer);
    return void_;
  });
};
var scopeAddFinalizerUnsafe = (scope, key, finalizer) => {
  if (scope.state._tag === "Empty") {
    scope.state = {
      _tag: "Open",
      finalizers: new Map([[key, finalizer]])
    };
  } else if (scope.state._tag === "Open") {
    scope.state.finalizers.set(key, finalizer);
  }
};
var scopeRemoveFinalizerUnsafe = (scope, key) => {
  if (scope.state._tag === "Open") {
    scope.state.finalizers.delete(key);
  }
};
var scopeMakeUnsafe = (finalizerStrategy = "sequential") => ({
  [ScopeCloseableTypeId]: ScopeCloseableTypeId,
  [ScopeTypeId]: ScopeTypeId,
  strategy: finalizerStrategy,
  state: constScopeEmpty
});
var constScopeEmpty = {
  _tag: "Empty"
};
var scope = /* @__PURE__ */ scopeTag.asEffect();
var provideScope = /* @__PURE__ */ provideService(scopeTag);
var scoped = (self) => withFiber((fiber2) => {
  const prev = fiber2.context;
  const scope2 = scopeMakeUnsafe();
  fiber2.setContext(add(fiber2.context, scopeTag, scope2));
  return onExitPrimitive(self, (exit2) => {
    fiber2.setContext(prev);
    return scopeCloseUnsafe(scope2, exit2);
  });
});
var scopedWith = (f) => suspend(() => {
  const scope2 = scopeMakeUnsafe();
  return onExit(f(scope2), (exit2) => suspend(() => scopeCloseUnsafe(scope2, exit2) ?? void_));
});
var acquireRelease = (acquire, release, options) => contextWith((context2) => uninterruptibleMask((restore) => flatMap(scope, (scope2) => tap(options?.interruptible ? restore(acquire) : acquire, (a) => scopeAddFinalizerExit(scope2, (exit2) => provideContext(release(a, exit2), context2))))));
var addFinalizer = (finalizer) => flatMap(scope, (scope2) => contextWith((context2) => scopeAddFinalizerExit(scope2, (exit2) => provideContext(finalizer(exit2), context2))));
var onExitPrimitive = /* @__PURE__ */ makePrimitive({
  op: "OnExit",
  single: false,
  [evaluate](fiber2) {
    fiber2._stack.push(this);
    return this[args][0];
  },
  [contAll](fiber2) {
    if (fiber2.interruptible && this[args][2] !== true) {
      fiber2._stack.push(setInterruptibleTrue);
      fiber2.interruptible = false;
    }
  },
  [contA](value, _, exit2) {
    exit2 ??= exitSucceed(value);
    const eff = this[args][1](exit2);
    return eff ? flatMap(eff, (_2) => exit2) : exit2;
  },
  [contE](cause, _, exit2) {
    exit2 ??= exitFailCause(cause);
    const eff = this[args][1](exit2);
    return eff ? flatMap(eff, (_2) => exit2) : exit2;
  }
});
var onExit = /* @__PURE__ */ dual(2, onExitPrimitive);
var ensuring = /* @__PURE__ */ dual(2, (self, finalizer) => onExit(self, (_) => finalizer));
var onExitIf = /* @__PURE__ */ dual(3, (self, predicate, f) => onExit(self, (exit2) => {
  if (!predicate(exit2)) {
    return void_;
  }
  return f(exit2);
}));
var onExitFilter = /* @__PURE__ */ dual(3, (self, filter3, f) => onExit(self, (exit2) => {
  const b = filter3(exit2);
  return isFailure2(b) ? void_ : f(b.success, exit2);
}));
var onError = /* @__PURE__ */ dual(2, (self, f) => onExitFilter(self, exitFilterCause, f));
var onErrorIf = /* @__PURE__ */ dual(3, (self, predicate, f) => onExitIf(self, (exit2) => {
  if (exit2._tag !== "Failure") {
    return false;
  }
  return predicate(exit2.cause);
}, (exit2) => f(exit2.cause)));
var onErrorFilter = /* @__PURE__ */ dual(3, (self, filter3, f) => onExit(self, (exit2) => {
  if (exit2._tag !== "Failure") {
    return void_;
  }
  const result2 = filter3(exit2.cause);
  return isFailure2(result2) ? void_ : f(result2.success, exit2.cause);
}));
var onInterrupt = /* @__PURE__ */ dual(2, (self, finalizer) => onErrorFilter(causeFilterInterruptors, finalizer)(self));
var acquireUseRelease = (acquire, use, release) => uninterruptibleMask((restore) => flatMap(acquire, (a) => onExitPrimitive(restore(use(a)), (exit2) => release(a, exit2), true)));
var cachedInvalidateWithTTL = /* @__PURE__ */ dual(2, (self, ttl) => sync(() => {
  const ttlMillis = toMillis(fromInputUnsafe(ttl));
  const isFinite = Number.isFinite(ttlMillis);
  const latch = makeLatchUnsafe(false);
  let expiresAt = 0;
  let running = false;
  let exit2;
  const wait = flatMap(latch.await, () => exit2);
  return [withFiber((fiber2) => {
    const clock = fiber2.getRef(ClockRef);
    const now = isFinite ? clock.currentTimeMillisUnsafe() : 0;
    if (running || now < expiresAt)
      return exit2 ?? wait;
    running = true;
    latch.closeUnsafe();
    exit2 = undefined;
    return onExit(self, (exit_) => sync(() => {
      running = false;
      expiresAt = clock.currentTimeMillisUnsafe() + ttlMillis;
      exit2 = exit_;
      latch.openUnsafe();
    }));
  }), sync(() => {
    expiresAt = 0;
    latch.closeUnsafe();
    exit2 = undefined;
  })];
}));
var cachedWithTTL = /* @__PURE__ */ dual(2, (self, timeToLive) => map4(cachedInvalidateWithTTL(self, timeToLive), (tuple) => tuple[0]));
var cached = (self) => cachedWithTTL(self, infinity);
var interrupt = /* @__PURE__ */ withFiber((fiber2) => failCause(causeInterrupt(fiber2.id)));
var uninterruptible = (self) => withFiber((fiber2) => {
  if (!fiber2.interruptible)
    return self;
  fiber2.interruptible = false;
  fiber2._stack.push(setInterruptibleTrue);
  return self;
});
var setInterruptible = /* @__PURE__ */ makePrimitive({
  op: "SetInterruptible",
  [contAll](fiber2) {
    fiber2.interruptible = this[args];
    if (fiber2._interruptedCause && fiber2.interruptible) {
      return () => failCause(fiber2._interruptedCause);
    }
  }
});
var setInterruptibleTrue = /* @__PURE__ */ setInterruptible(true);
var setInterruptibleFalse = /* @__PURE__ */ setInterruptible(false);
var interruptible = (self) => withFiber((fiber2) => {
  if (fiber2.interruptible)
    return self;
  fiber2.interruptible = true;
  fiber2._stack.push(setInterruptibleFalse);
  if (fiber2._interruptedCause)
    return failCause(fiber2._interruptedCause);
  return self;
});
var uninterruptibleMask = (f) => withFiber((fiber2) => {
  if (!fiber2.interruptible)
    return f(identity);
  fiber2.interruptible = false;
  fiber2._stack.push(setInterruptibleTrue);
  return f(interruptible);
});
var interruptibleMask = (f) => withFiber((fiber2) => {
  if (fiber2.interruptible)
    return f(identity);
  fiber2.interruptible = true;
  fiber2._stack.push(setInterruptibleFalse);
  return f(uninterruptible);
});
var abortSignal = /* @__PURE__ */ map4(/* @__PURE__ */ acquireRelease(/* @__PURE__ */ sync(() => new AbortController), (controller) => sync(() => controller.abort())), (_) => _.signal);
var all = (arg, options) => {
  if (isIterable(arg)) {
    return options?.mode === "result" ? forEach(arg, result, options) : forEach(arg, identity, options);
  } else if (options?.discard) {
    return options.mode === "result" ? forEach(Object.values(arg), result, options) : forEach(Object.values(arg), identity, options);
  }
  return suspend(() => {
    const out = {};
    return as(forEach(Object.entries(arg), ([key, effect]) => map4(options?.mode === "result" ? result(effect) : effect, (value) => {
      out[key] = value;
    }), {
      discard: true,
      concurrency: options?.concurrency
    }), out);
  });
};
var partition2 = /* @__PURE__ */ dual((args2) => isIterable(args2[0]) && !isEffect(args2[0]), (elements, f, options) => map4(forEach(elements, (a, i) => result(f(a, i)), options), (results) => partition(results, identity)));
var validate = /* @__PURE__ */ dual((args2) => isIterable(args2[0]) && !isEffect(args2[0]), (elements, f, options) => flatMap(partition2(elements, f, {
  concurrency: options?.concurrency
}), ([excluded, satisfying]) => {
  if (isArrayNonEmpty2(excluded)) {
    return fail3(excluded);
  }
  return options?.discard ? void_ : succeed3(satisfying);
}));
var findFirst = /* @__PURE__ */ dual((args2) => isIterable(args2[0]) && !isEffect(args2[0]), (elements, predicate) => suspend(() => {
  const iterator = elements[Symbol.iterator]();
  const next = iterator.next();
  if (!next.done) {
    return findFirstLoop(iterator, 0, predicate, next.value);
  }
  return succeed3(none2());
}));
var findFirstLoop = (iterator, index, predicate, value) => flatMap(predicate(value, index), (keep) => {
  if (keep) {
    return succeed3(some2(value));
  }
  const next = iterator.next();
  if (!next.done) {
    return findFirstLoop(iterator, index + 1, predicate, next.value);
  }
  return succeed3(none2());
});
var findFirstFilter = /* @__PURE__ */ dual((args2) => isIterable(args2[0]) && !isEffect(args2[0]), (elements, filter3) => suspend(() => {
  const iterator = elements[Symbol.iterator]();
  const next = iterator.next();
  if (!next.done) {
    return findFirstFilterLoop(iterator, 0, filter3, next.value);
  }
  return succeed3(none2());
}));
var findFirstFilterLoop = (iterator, index, filter3, value) => flatMap(filter3(value, index), (result2) => {
  if (isSuccess2(result2)) {
    return succeed3(some2(result2.success));
  }
  const next = iterator.next();
  if (!next.done) {
    return findFirstFilterLoop(iterator, index + 1, filter3, next.value);
  }
  return succeed3(none2());
});
var whileLoop = /* @__PURE__ */ makePrimitive({
  op: "While",
  [contA](value, fiber2) {
    this[args].step(value);
    if (this[args].while()) {
      fiber2._stack.push(this);
      return this[args].body();
    }
    return exitVoid;
  },
  [evaluate](fiber2) {
    if (this[args].while()) {
      fiber2._stack.push(this);
      return this[args].body();
    }
    return exitVoid;
  }
});
var forEach = /* @__PURE__ */ dual((args2) => typeof args2[1] === "function", (iterable, f, options) => withFiber((parent) => {
  const concurrencyOption = options?.concurrency === "inherit" ? parent.getRef(CurrentConcurrency) : options?.concurrency ?? 1;
  const concurrency = concurrencyOption === "unbounded" ? Number.POSITIVE_INFINITY : Math.max(1, concurrencyOption);
  if (concurrency === 1) {
    return forEachSequential(iterable, f, options);
  }
  const items = fromIterable(iterable);
  let length = items.length;
  if (length === 0) {
    return options?.discard ? void_ : succeed3([]);
  }
  const out = options?.discard ? undefined : new Array(length);
  const eff = forEachConcurrent({
    f,
    out
  }, items, {
    concurrency
  });
  return eff ? as(eff, out) : succeed3(out);
}));
var forEachSequential = (iterable, f, options) => suspend(() => {
  const out = options?.discard ? undefined : [];
  const iterator = iterable[Symbol.iterator]();
  let state = iterator.next();
  let index = 0;
  return as(whileLoop({
    while: () => !state.done,
    body: () => f(state.value, index++),
    step: (b) => {
      if (out)
        out.push(b);
      state = iterator.next();
    }
  }), out);
});
var iterateEagerImpl = (options) => {
  const onItem = options.onItem;
  const step = options.step;
  return (state, items, opts) => {
    let index = opts?.start ?? 0;
    const end = opts?.end ?? items.length;
    const concurrency = opts?.concurrency ?? 1;
    let done2 = false;
    let parentFiber;
    let fibers;
    let resume;
    let interrupted = false;
    let terminal;
    let effect;
    const go = () => {
      let paused = false;
      for (;!terminal && index < end; index++) {
        const item = items[index];
        const eff = effect ?? onItem(state, item, index);
        if (effectIsExit(eff)) {
          terminal = step(state, item, eff, index);
          if (terminal)
            break;
        } else if (concurrency === 1) {
          return flatMap(exit(eff), (exit2) => {
            terminal = step(state, item, exit2, index);
            index++;
            return terminal ?? go() ?? void_;
          });
        } else if (!parentFiber) {
          return callback((cb) => {
            parentFiber = getCurrentFiber();
            effect = eff;
            resume = cb;
            const result2 = go();
            if (result2)
              return cb(result2);
            return suspend(() => {
              terminal = exitVoid;
              interrupted = true;
              return fibers ? fiberInterruptAll(fibers) : void_;
            });
          });
        } else {
          effect = undefined;
          const fiber2 = forkUnsafe(parentFiber, eff, true, true, "inherit");
          if (fiber2._exit) {
            terminal = step(state, item, fiber2._exit, index);
            if (terminal)
              break;
            continue;
          }
          if (fibers)
            fibers.add(fiber2);
          else
            fibers = new Set([fiber2]);
          const currentIndex = index;
          fiber2.addObserver((exit2) => {
            fibers.delete(fiber2);
            if (terminal) {
              if (!interrupted && exit2._tag === "Failure") {
                for (const reason of exit2.cause.reasons) {
                  if (reason._tag === "Interrupt")
                    continue;
                  else if (terminal._tag === "Failure") {
                    terminal.cause.reasons.push(reason);
                  } else {
                    terminal = exitFailCause(causeFromReasons([reason]));
                  }
                }
              }
            } else {
              const result2 = step(state, item, exit2, currentIndex);
              if (result2) {
                terminal = result2._tag === "Failure" ? exitFailCause(causeFromReasons(result2.cause.reasons.slice())) : result2;
                go();
              }
            }
            if (paused) {
              const eff2 = go();
              if (eff2)
                resume(eff2);
            } else if (done2 && fibers.size === 0) {
              resume(terminal ?? void_);
            }
          });
          if (fibers.size < concurrency)
            continue;
          paused = true;
          index++;
          return;
        }
      }
      done2 = true;
      if (terminal) {
        if (fibers && fibers.size > 0) {
          const annotations = fiberStackAnnotations(parentFiber);
          fibers.forEach((f) => f.interruptUnsafe(parentFiber.id, annotations));
          return;
        }
        if (resume || terminal._tag === "Failure") {
          return terminal;
        }
      } else if (resume) {
        if (!fibers) {
          return exitVoid;
        } else if (fibers.size === 0) {
          resume(void_);
        }
      }
    };
    return go();
  };
};
var iterateEager = () => iterateEagerImpl;
var forEachConcurrent = /* @__PURE__ */ iterateEagerImpl({
  onItem(state, item, index) {
    return state.f(item, index);
  },
  step(state, _, exit2, index) {
    if (exit2._tag === "Failure")
      return exit2;
    else if (state.out) {
      state.out[index] = exit2.value;
    }
  }
});
var filterOrElse = /* @__PURE__ */ dual(3, (self, predicate, orElse) => flatMap(self, (a) => predicate(a) ? succeed3(a) : orElse(a)));
var filterMapOrElse = /* @__PURE__ */ dual(3, (self, filter3, orElse) => flatMap(self, (a) => {
  const result2 = filter3(a);
  return isFailure2(result2) ? orElse(result2.failure) : succeed3(result2.success);
}));
var filterMapOrFail = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, filter3, orFailWith) => filterMapOrElse(self, filter3, orFailWith ? (x) => fail3(orFailWith(x)) : () => fail3(new NoSuchElementError)));
var filter3 = /* @__PURE__ */ dual((args2) => isIterable(args2[0]) && !isEffect(args2[0]), (elements, predicate, options) => suspend(() => {
  const out = [];
  return as(forEach(elements, (a, i) => {
    const result2 = predicate(a, i);
    if (typeof result2 === "boolean") {
      if (result2)
        out.push(a);
      return void_;
    }
    return map4(result2, (keep) => {
      if (keep) {
        out.push(a);
      }
    });
  }, {
    discard: true,
    concurrency: options?.concurrency
  }), out);
}));
var filterMap = /* @__PURE__ */ dual((args2) => isIterable(args2[0]) && !isEffect(args2[0]), (elements, filter4) => suspend(() => {
  const out = [];
  for (const a of elements) {
    const result2 = filter4(a);
    if (isSuccess2(result2)) {
      out.push(result2.success);
    }
  }
  return succeed3(out);
}));
var filterMapEffect = /* @__PURE__ */ dual((args2) => isIterable(args2[0]) && !isEffect(args2[0]), (elements, filter4, options) => suspend(() => {
  const out = [];
  return as(forEach(elements, (a) => map4(filter4(a), (result2) => {
    if (isSuccess2(result2)) {
      out.push(result2.success);
    }
  }), {
    discard: true,
    concurrency: options?.concurrency
  }), out);
}));
var Do = /* @__PURE__ */ succeed3({});
var bindTo2 = /* @__PURE__ */ bindTo(map4);
var bind2 = /* @__PURE__ */ bind(map4, flatMap);
var let_2 = /* @__PURE__ */ let_(map4);
var forkChild = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, options) => withFiber((fiber2) => {
  interruptChildrenPatch();
  return succeed3(forkUnsafe(fiber2, self, options?.startImmediately, false, options?.uninterruptible ?? false));
}));
var forkUnsafe = (parent, effect, immediate = false, daemon = false, uninterruptible2 = false) => {
  const interruptible2 = uninterruptible2 === "inherit" ? parent.interruptible : !uninterruptible2;
  const child = new FiberImpl(parent.context, interruptible2);
  if (immediate) {
    child.evaluate(effect);
  } else {
    parent.currentDispatcher.scheduleTask(() => child.evaluate(effect), 0);
  }
  if (!daemon && !child._exit) {
    parent.children().add(child);
    child.addObserver(() => parent._children.delete(child));
  }
  return child;
};
var forkDetach = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, options) => withFiber((fiber2) => succeed3(forkUnsafe(fiber2, self, options?.startImmediately, true, options?.uninterruptible))));
var awaitAllChildren = (self) => withFiber((fiber2) => {
  const initialChildren = fiber2._children && fromIterable(fiber2._children);
  return onExit(self, (_) => {
    let children = fiber2._children;
    if (children === undefined || children.size === 0) {
      return void_;
    } else if (initialChildren) {
      children = filter2(children, (child) => !initialChildren.includes(child));
    }
    return asVoid(fiberAwaitAll(children));
  });
});
var forkIn = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, scope2, options) => withFiber((parent) => {
  const fiber2 = forkUnsafe(parent, self, options?.startImmediately, true, options?.uninterruptible);
  if (!fiber2._exit) {
    if (scope2.state._tag !== "Closed") {
      const key = {};
      const finalizer = () => withFiberId((interruptor) => interruptor === fiber2.id ? void_ : fiberInterrupt(fiber2));
      scopeAddFinalizerUnsafe(scope2, key, finalizer);
      fiber2.addObserver(() => scopeRemoveFinalizerUnsafe(scope2, key));
    } else {
      fiber2.interruptUnsafe(parent.id, fiberStackAnnotations(parent));
    }
  }
  return succeed3(fiber2);
}));
var forkScoped = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, options) => flatMap(scope, (scope2) => forkIn(self, scope2, options)));
var runForkWith = (context2) => (effect, options) => {
  const fiber2 = new FiberImpl(options?.scheduler ? add(context2, Scheduler, options.scheduler) : context2, options?.uninterruptible !== true);
  fiber2.evaluate(effect);
  if (fiber2._exit)
    return fiber2;
  if (options?.signal) {
    if (options.signal.aborted) {
      fiber2.interruptUnsafe();
    } else {
      const abort = () => fiber2.interruptUnsafe();
      options.signal.addEventListener("abort", abort, {
        once: true
      });
      fiber2.addObserver(() => options.signal.removeEventListener("abort", abort));
    }
  }
  if (options?.onFiberStart) {
    options.onFiberStart(fiber2);
  }
  return fiber2;
};
var runFork = /* @__PURE__ */ runForkWith(/* @__PURE__ */ empty2());
var runCallbackWith = (context2) => {
  const runFork2 = runForkWith(context2);
  return (effect, options) => {
    const fiber2 = runFork2(effect, options);
    if (options?.onExit) {
      fiber2.addObserver(options.onExit);
    }
    return (interruptor) => {
      return fiber2.interruptUnsafe(interruptor);
    };
  };
};
var runCallback = /* @__PURE__ */ runCallbackWith(/* @__PURE__ */ empty2());
var runPromiseExitWith = (context2) => {
  const runFork2 = runForkWith(context2);
  return (effect, options) => {
    const fiber2 = runFork2(effect, options);
    return new Promise((resolve) => {
      fiber2.addObserver((exit2) => resolve(exit2));
    });
  };
};
var runPromiseExit = /* @__PURE__ */ runPromiseExitWith(/* @__PURE__ */ empty2());
var runPromiseWith = (context2) => {
  const runPromiseExit2 = runPromiseExitWith(context2);
  return (effect, options) => runPromiseExit2(effect, options).then((exit2) => {
    if (exit2._tag === "Failure") {
      throw causeSquash(exit2.cause);
    }
    return exit2.value;
  });
};
var runPromise = /* @__PURE__ */ runPromiseWith(/* @__PURE__ */ empty2());
var runSyncExitWith = (context2) => {
  const runFork2 = runForkWith(context2);
  return (effect) => {
    if (effectIsExit(effect))
      return effect;
    const scheduler = new MixedScheduler("sync");
    const fiber2 = runFork2(effect, {
      scheduler
    });
    fiber2.currentDispatcher?.flush();
    return fiber2._exit ?? exitDie(new AsyncFiberError(fiber2));
  };
};
var runSyncExit = /* @__PURE__ */ runSyncExitWith(/* @__PURE__ */ empty2());
var runSyncWith = (context2) => {
  const runSyncExit2 = runSyncExitWith(context2);
  return (effect) => {
    const exit2 = runSyncExit2(effect);
    if (exit2._tag === "Failure")
      throw causeSquash(exit2.cause);
    return exit2.value;
  };
};
var runSync = /* @__PURE__ */ runSyncWith(/* @__PURE__ */ empty2());
var succeedTrue = /* @__PURE__ */ succeed3(true);
var succeedFalse = /* @__PURE__ */ succeed3(false);

class Latch {
  waiters = [];
  scheduled = false;
  isOpen;
  constructor(isOpen) {
    this.isOpen = isOpen;
  }
  scheduleUnsafe(fiber2) {
    if (this.scheduled || this.waiters.length === 0) {
      return succeedTrue;
    }
    this.scheduled = true;
    fiber2.currentDispatcher.scheduleTask(this.flushWaiters, 0);
    return succeedTrue;
  }
  flushWaiters = () => {
    this.scheduled = false;
    const waiters = this.waiters;
    this.waiters = [];
    for (let i = 0;i < waiters.length; i++) {
      waiters[i](exitVoid);
    }
  };
  open = /* @__PURE__ */ withFiber((fiber2) => {
    if (this.isOpen)
      return succeedFalse;
    this.isOpen = true;
    return this.scheduleUnsafe(fiber2);
  });
  release = /* @__PURE__ */ withFiber((fiber2) => this.isOpen ? succeedFalse : this.scheduleUnsafe(fiber2));
  openUnsafe() {
    if (this.isOpen)
      return false;
    this.isOpen = true;
    this.flushWaiters();
    return true;
  }
  await = /* @__PURE__ */ callback((resume) => {
    if (this.isOpen) {
      return resume(void_);
    }
    this.waiters.push(resume);
    return sync(() => {
      const index = this.waiters.indexOf(resume);
      if (index !== -1) {
        this.waiters.splice(index, 1);
      }
    });
  });
  closeUnsafe() {
    if (!this.isOpen)
      return false;
    this.isOpen = false;
    return true;
  }
  close = /* @__PURE__ */ sync(() => this.closeUnsafe());
  whenOpen = (self) => flatMap(this.await, () => self);
}
var makeLatchUnsafe = (open) => new Latch(open ?? false);
var tracer = /* @__PURE__ */ withFiber((fiber2) => succeed3(fiber2.getRef(Tracer)));
var withTracer = /* @__PURE__ */ dual(2, (effect, tracer2) => provideService(effect, Tracer, tracer2));
var withTracerEnabled = /* @__PURE__ */ provideService(TracerEnabled);
var withTracerTiming = /* @__PURE__ */ provideService(TracerTimingEnabled);
var bigint02 = /* @__PURE__ */ BigInt(0);
var NoopSpanProto = {
  _tag: "Span",
  spanId: "noop",
  traceId: "noop",
  sampled: false,
  status: {
    _tag: "Ended",
    startTime: bigint02,
    endTime: bigint02,
    exit: exitVoid
  },
  attributes: /* @__PURE__ */ new Map,
  links: [],
  kind: "internal",
  attribute() {},
  event() {},
  end() {},
  addLinks() {}
};
var noopSpan = (options) => Object.assign(Object.create(NoopSpanProto), options);
var filterDisablePropagation = (span) => {
  if (!span)
    return none2();
  return get(span.annotations, DisablePropagation) ? span._tag === "Span" ? filterDisablePropagation(getOrUndefined(span.parent)) : none2() : some2(span);
};
var makeSpanUnsafe = (fiber2, name, options) => {
  const disablePropagation = !fiber2.getRef(TracerEnabled) || options?.annotations && get(options.annotations, DisablePropagation);
  const parent = options?.parent !== undefined ? some2(options.parent) : options?.root ? none2() : filterDisablePropagation(fiber2.currentSpan);
  let span;
  if (disablePropagation) {
    span = noopSpan({
      name,
      parent,
      annotations: add(options?.annotations ?? empty2(), DisablePropagation, true)
    });
  } else {
    const tracer2 = fiber2.getRef(Tracer);
    const clock = fiber2.getRef(ClockRef);
    const timingEnabled = fiber2.getRef(TracerTimingEnabled);
    const annotationsFromEnv = fiber2.getRef(TracerSpanAnnotations);
    const linksFromEnv = fiber2.getRef(TracerSpanLinks);
    const level = options?.level ?? fiber2.getRef(CurrentTraceLevel);
    const links = options?.links !== undefined ? [...linksFromEnv, ...options.links] : linksFromEnv.slice();
    span = tracer2.span({
      name,
      parent,
      annotations: options?.annotations ?? empty2(),
      links,
      startTime: timingEnabled ? clock.currentTimeNanosUnsafe() : BigInt(0),
      kind: options?.kind ?? "internal",
      root: options?.root ?? isNone2(parent),
      sampled: options?.sampled ?? (isSome2(parent) && parent.value.sampled === false ? false : !isLogLevelGreaterThan(fiber2.getRef(MinimumTraceLevel), level))
    });
    for (const [key, value] of Object.entries(annotationsFromEnv)) {
      span.attribute(key, value);
    }
    if (options?.attributes !== undefined) {
      for (const [key, value] of Object.entries(options.attributes)) {
        span.attribute(key, value);
      }
    }
  }
  return span;
};
var makeSpan = (name, options) => withFiber((fiber2) => succeed3(makeSpanUnsafe(fiber2, name, options)));
var makeSpanScoped = (name, options) => uninterruptible(withFiber((fiber2) => {
  const scope2 = getUnsafe2(fiber2.context, scopeTag);
  const span = makeSpanUnsafe(fiber2, name, options ?? {});
  const clock = fiber2.getRef(ClockRef);
  const timingEnabled = fiber2.getRef(TracerTimingEnabled);
  return as(scopeAddFinalizerExit(scope2, (exit2) => endSpan(span, exit2, clock, timingEnabled)), span);
}));
var withSpanScoped = function() {
  const dataFirst = typeof arguments[0] !== "string";
  const name = dataFirst ? arguments[1] : arguments[0];
  const options = addSpanStackTrace(dataFirst ? arguments[2] : arguments[1]);
  if (dataFirst) {
    const self = arguments[0];
    return flatMap(makeSpanScoped(name, options), (span) => withParentSpan(self, span, options));
  }
  return (self) => flatMap(makeSpanScoped(name, options), (span) => withParentSpan(self, span, options));
};
var provideSpanStackFrame = (name, stack) => {
  stack = typeof stack === "function" ? stack : constUndefined;
  return updateService(CurrentStackFrame, (parent) => ({
    name,
    stack,
    parent
  }));
};
var spanAnnotations = /* @__PURE__ */ TracerSpanAnnotations.asEffect();
var spanLinks = /* @__PURE__ */ TracerSpanLinks.asEffect();
var linkSpans = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, span, attributes = {}) => {
  const spans = Array.isArray(span) ? span : [span];
  const links = spans.map((span2) => ({
    span: span2,
    attributes
  }));
  return updateService(self, TracerSpanLinks, (current) => [...current, ...links]);
});
var endSpan = (span, exit2, clock, timingEnabled) => sync(() => {
  if (span.status._tag === "Ended")
    return;
  span.end(timingEnabled ? clock.currentTimeNanosUnsafe() : bigint02, exit2);
});
var useSpan = (name, ...args2) => {
  const options = args2.length === 1 ? undefined : args2[0];
  const evaluate2 = args2[args2.length - 1];
  return withFiber((fiber2) => {
    const span = makeSpanUnsafe(fiber2, name, options);
    const clock = fiber2.getRef(ClockRef);
    return onExit(internalCall(() => evaluate2(span)), (exit2) => sync(() => {
      if (span.status._tag === "Ended")
        return;
      span.end(clock.currentTimeNanosUnsafe(), exit2);
    }));
  });
};
var provideParentSpan = /* @__PURE__ */ provideService(ParentSpan);
var withParentSpan = function() {
  const dataFirst = isEffect(arguments[0]);
  const span = dataFirst ? arguments[1] : arguments[0];
  let options = dataFirst ? arguments[2] : arguments[1];
  let provideStackFrame = identity;
  if (span._tag === "Span") {
    options = addSpanStackTrace(options);
    provideStackFrame = provideSpanStackFrame(span.name, options?.captureStackTrace);
  }
  if (dataFirst) {
    return provideParentSpan(provideStackFrame(arguments[0]), span);
  }
  return (self) => provideParentSpan(provideStackFrame(self), span);
};
var withSpan = function() {
  const dataFirst = typeof arguments[0] !== "string";
  const name = dataFirst ? arguments[1] : arguments[0];
  const traceOptions = addSpanStackTrace(arguments[2]);
  if (dataFirst) {
    const self = arguments[0];
    return useSpan(name, arguments[2], (span) => withParentSpan(self, span, traceOptions));
  }
  const fnArg = typeof arguments[1] === "function" ? arguments[1] : undefined;
  const options = fnArg ? undefined : arguments[1];
  return (self, ...args2) => useSpan(name, fnArg ? fnArg(...args2) : options, (span) => withParentSpan(self, span, traceOptions));
};
var annotateSpans = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (effect, ...args2) => updateService(effect, TracerSpanAnnotations, (annotations) => {
  const newAnnotations = {
    ...annotations
  };
  if (args2.length === 1) {
    Object.assign(newAnnotations, args2[0]);
  } else {
    newAnnotations[args2[0]] = args2[1];
  }
  return newAnnotations;
}));
var annotateCurrentSpan = (...args2) => withFiber((fiber2) => {
  const span = fiber2.currentSpanLocal;
  if (span) {
    if (args2.length === 1) {
      for (const [key, value] of Object.entries(args2[0])) {
        span.attribute(key, value);
      }
    } else {
      span.attribute(args2[0], args2[1]);
    }
  }
  return void_;
});
var currentSpan = /* @__PURE__ */ withFiber((fiber2) => {
  const span = fiber2.currentSpanLocal;
  return span ? succeed3(span) : fail3(new NoSuchElementError);
});
var currentParentSpan = /* @__PURE__ */ serviceOptional(ParentSpan);
var ClockRef = /* @__PURE__ */ Reference("effect/Clock", {
  defaultValue: () => new ClockImpl
});
var MAX_TIMER_MILLIS = 2 ** 31 - 1;

class ClockImpl {
  currentTimeMillisUnsafe() {
    return Date.now();
  }
  currentTimeMillis = /* @__PURE__ */ sync(() => this.currentTimeMillisUnsafe());
  currentTimeNanosUnsafe() {
    return processOrPerformanceNow();
  }
  currentTimeNanos = /* @__PURE__ */ sync(() => this.currentTimeNanosUnsafe());
  sleep(duration) {
    const millis2 = toMillis(duration);
    if (millis2 <= 0)
      return yieldNow;
    return callback((resume) => {
      if (millis2 > MAX_TIMER_MILLIS)
        return;
      const handle = setTimeout(() => resume(void_), millis2);
      return sync(() => clearTimeout(handle));
    });
  }
}
var performanceNowNanos = /* @__PURE__ */ function() {
  const bigint1e62 = /* @__PURE__ */ BigInt(1e6);
  if (typeof performance === "undefined" || typeof performance.now === "undefined") {
    return () => BigInt(Date.now()) * bigint1e62;
  } else if (typeof performance.timeOrigin === "number" && performance.timeOrigin === 0) {
    return () => BigInt(Math.round(performance.now() * 1e6));
  }
  const origin = /* @__PURE__ */ BigInt(/* @__PURE__ */ Date.now()) * bigint1e62 - /* @__PURE__ */ BigInt(/* @__PURE__ */ Math.round(/* @__PURE__ */ performance.now() * 1e6));
  return () => origin + BigInt(Math.round(performance.now() * 1e6));
}();
var processOrPerformanceNow = /* @__PURE__ */ function() {
  const processHrtime = typeof process === "object" && "hrtime" in process && typeof process.hrtime.bigint === "function" ? process.hrtime : undefined;
  if (!processHrtime) {
    return performanceNowNanos;
  }
  const origin = /* @__PURE__ */ performanceNowNanos() - /* @__PURE__ */ processHrtime.bigint();
  return () => origin + processHrtime.bigint();
}();
var clockWith = (f) => withFiber((fiber2) => f(fiber2.getRef(ClockRef)));
var sleep = (duration) => clockWith((clock) => clock.sleep(fromInputUnsafe(duration)));
var currentTimeMillis = /* @__PURE__ */ clockWith((clock) => clock.currentTimeMillis);
var TimeoutErrorTypeId = "~effect/Cause/TimeoutError";
class TimeoutError extends (/* @__PURE__ */ TaggedError("TimeoutError")) {
  [TimeoutErrorTypeId] = TimeoutErrorTypeId;
  constructor(message) {
    super({
      message
    });
  }
}
var AsyncFiberErrorTypeId = "~effect/Cause/AsyncFiberError";
class AsyncFiberError extends (/* @__PURE__ */ TaggedError("AsyncFiberError")) {
  [AsyncFiberErrorTypeId] = AsyncFiberErrorTypeId;
  constructor(fiber2) {
    super({
      message: "An asynchronous Effect was executed with Effect.runSync",
      fiber: fiber2
    });
  }
}
var UnknownErrorTypeId = "~effect/Cause/UnknownError";
class UnknownError extends (/* @__PURE__ */ TaggedError("UnknownError")) {
  [UnknownErrorTypeId] = UnknownErrorTypeId;
  constructor(cause, message) {
    super({
      message,
      cause
    });
  }
}
var ConsoleRef = /* @__PURE__ */ Reference("effect/Console/CurrentConsole", {
  defaultValue: () => globalThis.console
});
var logLevelToOrder = (level) => {
  switch (level) {
    case "All":
      return Number.MIN_SAFE_INTEGER;
    case "Fatal":
      return 50000;
    case "Error":
      return 40000;
    case "Warn":
      return 30000;
    case "Info":
      return 20000;
    case "Debug":
      return 1e4;
    case "Trace":
      return 0;
    case "None":
      return Number.MAX_SAFE_INTEGER;
  }
};
var LogLevelOrder = /* @__PURE__ */ mapInput(Number2, logLevelToOrder);
var isLogLevelGreaterThan = /* @__PURE__ */ isGreaterThan(LogLevelOrder);
var CurrentLoggers = /* @__PURE__ */ Reference("effect/Loggers/CurrentLoggers", {
  defaultValue: () => new Set([defaultLogger, tracerLogger])
});
var LogToStderr = /* @__PURE__ */ Reference("effect/Logger/LogToStderr", {
  defaultValue: constFalse
});
var annotateLogsScoped = function() {
  const entries = typeof arguments[0] === "string" ? [[arguments[0], arguments[1]]] : Object.entries(arguments[0]);
  return uninterruptible(withFiber((fiber2) => {
    const prev = fiber2.getRef(CurrentLogAnnotations);
    const next = {
      ...prev
    };
    for (let i = 0;i < entries.length; i++) {
      const [key, value] = entries[i];
      next[key] = value;
    }
    fiber2.setContext(add(fiber2.context, CurrentLogAnnotations, next));
    return scopeAddFinalizerExit(getUnsafe2(fiber2.context, scopeTag), (_) => {
      const current = fiber2.getRef(CurrentLogAnnotations);
      const next2 = {
        ...current
      };
      for (let i = 0;i < entries.length; i++) {
        const [key, value] = entries[i];
        if (current[key] !== value)
          continue;
        if (key in prev) {
          next2[key] = prev[key];
        } else {
          delete next2[key];
        }
      }
      fiber2.setContext(add(fiber2.context, CurrentLogAnnotations, next2));
      return void_;
    });
  }));
};
var LoggerTypeId = "~effect/Logger";
var LoggerProto = {
  [LoggerTypeId]: {
    _Message: identity,
    _Output: identity
  },
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var loggerMake = (log) => {
  const self = Object.create(LoggerProto);
  self.log = log;
  return self;
};
var formatLabel = (key) => key.replace(/[\s="]/g, "_");
var formatLogSpan = (self, now) => {
  const label = formatLabel(self[0]);
  return `${label}=${now - self[1]}ms`;
};
var logWithLevel = (level) => (...message) => {
  let cause = undefined;
  for (let i = 0, len = message.length;i < len; i++) {
    const msg = message[i];
    if (isCause(msg)) {
      if (cause) {
        message.splice(i, 1);
      } else {
        message = message.slice(0, i).concat(message.slice(i + 1));
      }
      cause = cause ? causeFromReasons(cause.reasons.concat(msg.reasons)) : msg;
      i--;
    }
  }
  if (cause === undefined) {
    cause = causeEmpty;
  }
  return withFiber((fiber2) => {
    const logLevel = level ?? fiber2.currentLogLevel;
    if (isLogLevelGreaterThan(fiber2.minimumLogLevel, logLevel)) {
      return void_;
    }
    const clock = fiber2.getRef(ClockRef);
    const loggers = fiber2.getRef(CurrentLoggers);
    if (loggers.size > 0) {
      const date = new Date(clock.currentTimeMillisUnsafe());
      for (const logger of loggers) {
        logger.log({
          cause,
          fiber: fiber2,
          date,
          logLevel,
          message
        });
      }
    }
    return void_;
  });
};
var colors = {
  bold: "1",
  red: "31",
  green: "32",
  yellow: "33",
  blue: "34",
  cyan: "36",
  white: "37",
  gray: "90",
  black: "30",
  bgBrightRed: "101"
};
var logLevelColors = {
  None: [],
  All: [],
  Trace: [colors.gray],
  Debug: [colors.blue],
  Info: [colors.green],
  Warn: [colors.yellow],
  Error: [colors.red],
  Fatal: [colors.bgBrightRed, colors.black]
};
var defaultDateFormat = (date) => `${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}:${date.getSeconds().toString().padStart(2, "0")}.${date.getMilliseconds().toString().padStart(3, "0")}`;
var hasProcessStdout = typeof process === "object" && process !== null && typeof process.stdout === "object" && process.stdout !== null;
var processStdoutIsTTY = hasProcessStdout && process.stdout.isTTY === true;
var hasProcessStdoutOrDeno = hasProcessStdout || "Deno" in globalThis;
var defaultLogger = /* @__PURE__ */ loggerMake(({
  cause,
  date,
  fiber: fiber2,
  logLevel,
  message
}) => {
  const message_ = Array.isArray(message) ? message.slice() : [message];
  if (cause.reasons.length > 0) {
    message_.push(causePretty(cause));
  }
  const now = date.getTime();
  const spans = fiber2.getRef(CurrentLogSpans);
  let spanString = "";
  for (const span of spans) {
    spanString += ` ${formatLogSpan(span, now)}`;
  }
  const annotations = fiber2.getRef(CurrentLogAnnotations);
  if (Object.keys(annotations).length > 0) {
    message_.push(annotations);
  }
  const console2 = fiber2.getRef(ConsoleRef);
  const log = fiber2.getRef(LogToStderr) ? console2.error : console2.log;
  log(`[${defaultDateFormat(date)}] ${logLevel.toUpperCase()} (#${fiber2.id})${spanString}:`, ...message_);
});
var tracerLogger = /* @__PURE__ */ loggerMake(({
  cause,
  fiber: fiber2,
  logLevel,
  message
}) => {
  const clock = fiber2.getRef(ClockRef);
  const annotations = fiber2.getRef(CurrentLogAnnotations);
  const span = fiber2.currentSpan;
  if (span === undefined || span._tag === "ExternalSpan")
    return;
  const attributes = {};
  for (const [key, value] of Object.entries(annotations)) {
    attributes[key] = value;
  }
  attributes["effect.fiberId"] = fiber2.id;
  attributes["effect.logLevel"] = logLevel.toUpperCase();
  if (cause.reasons.length > 0) {
    attributes["effect.cause"] = causePretty(cause);
  }
  span.event(toStringUnknown(Array.isArray(message) && message.length === 1 ? message[0] : message), clock.currentTimeNanosUnsafe(), attributes);
});
function interruptChildrenPatch() {
  fiberMiddleware.interruptChildren ??= fiberInterruptChildren;
}
var undefined_ = /* @__PURE__ */ succeed3(undefined);
var withErrorReporting = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, options) => onError(self, (cause) => withFiber((fiber2) => {
  reportCauseUnsafe(fiber2, cause, options?.defectsOnly);
  return void_;
})));
var reportCauseUnsafe = (fiber2, cause, defectsOnly) => {
  const reporters = fiber2.getRef(CurrentErrorReporters);
  if (reporters.size === 0)
    return;
  if (defectsOnly && !hasDies(cause))
    return;
  const opts = {
    cause,
    fiber: fiber2,
    timestamp: fiber2.getRef(ClockRef).currentTimeNanosUnsafe()
  };
  reporters.forEach((reporter) => reporter.report(opts));
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Cause.js
var findError2 = findError;
var isDone2 = isDone;
var done2 = done;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Data.js
var TaggedError2 = TaggedError;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Effect.js
var exports_Effect = {};
__export(exports_Effect, {
  zipWith: () => zipWith2,
  zip: () => zip2,
  yieldNowWith: () => yieldNowWith2,
  yieldNow: () => yieldNow2,
  withTracerTiming: () => withTracerTiming2,
  withTracerEnabled: () => withTracerEnabled2,
  withTracer: () => withTracer2,
  withSpanScoped: () => withSpanScoped2,
  withSpan: () => withSpan3,
  withParentSpan: () => withParentSpan3,
  withLogger: () => withLogger,
  withLogSpan: () => withLogSpan,
  withFiber: () => withFiber2,
  withExecutionPlan: () => withExecutionPlan2,
  withErrorReporting: () => withErrorReporting2,
  withConcurrency: () => withConcurrency2,
  whileLoop: () => whileLoop2,
  when: () => when2,
  void: () => void_3,
  validate: () => validate2,
  useSpan: () => useSpan2,
  updateService: () => updateService3,
  updateContext: () => updateContext2,
  unwrapReason: () => unwrapReason2,
  uninterruptibleMask: () => uninterruptibleMask2,
  uninterruptible: () => uninterruptible2,
  undefined: () => undefined_2,
  txRetry: () => txRetry,
  tx: () => tx,
  tryPromise: () => tryPromise2,
  try: () => try_2,
  trackSuccesses: () => trackSuccesses,
  trackErrors: () => trackErrors,
  trackDuration: () => trackDuration,
  trackDefects: () => trackDefects,
  track: () => track,
  tracer: () => tracer2,
  timeoutOrElse: () => timeoutOrElse2,
  timeoutOption: () => timeoutOption2,
  timeout: () => timeout2,
  timed: () => timed2,
  tapErrorTag: () => tapErrorTag2,
  tapError: () => tapError3,
  tapDefect: () => tapDefect2,
  tapCauseIf: () => tapCauseIf2,
  tapCauseFilter: () => tapCauseFilter2,
  tapCause: () => tapCause3,
  tap: () => tap3,
  sync: () => sync3,
  suspend: () => suspend3,
  succeedSome: () => succeedSome2,
  succeedNone: () => succeedNone2,
  succeed: () => succeed5,
  spanLinks: () => spanLinks2,
  spanAnnotations: () => spanAnnotations2,
  sleep: () => sleep2,
  serviceOption: () => serviceOption2,
  service: () => service2,
  scopedWith: () => scopedWith2,
  scoped: () => scoped2,
  scope: () => scope2,
  scheduleFrom: () => scheduleFrom2,
  schedule: () => schedule,
  satisfiesSuccessType: () => satisfiesSuccessType2,
  satisfiesServicesType: () => satisfiesServicesType2,
  satisfiesErrorType: () => satisfiesErrorType2,
  sandbox: () => sandbox2,
  runSyncWith: () => runSyncWith2,
  runSyncExitWith: () => runSyncExitWith2,
  runSyncExit: () => runSyncExit2,
  runSync: () => runSync2,
  runPromiseWith: () => runPromiseWith2,
  runPromiseExitWith: () => runPromiseExitWith2,
  runPromiseExit: () => runPromiseExit2,
  runPromise: () => runPromise2,
  runForkWith: () => runForkWith2,
  runFork: () => runFork2,
  runCallbackWith: () => runCallbackWith2,
  runCallback: () => runCallback2,
  retryOrElse: () => retryOrElse2,
  retry: () => retry2,
  result: () => result2,
  requestUnsafe: () => requestUnsafe2,
  request: () => request2,
  replicateEffect: () => replicateEffect2,
  replicate: () => replicate2,
  repeatOrElse: () => repeatOrElse2,
  repeat: () => repeat2,
  raceFirst: () => raceFirst2,
  raceAllFirst: () => raceAllFirst2,
  raceAll: () => raceAll2,
  race: () => race2,
  provideServiceEffect: () => provideServiceEffect2,
  provideService: () => provideService2,
  provideContext: () => provideContext2,
  provide: () => provide4,
  promise: () => promise2,
  partition: () => partition3,
  orElseSucceed: () => orElseSucceed2,
  orDie: () => orDie3,
  option: () => option2,
  onInterrupt: () => onInterrupt2,
  onExitPrimitive: () => onExitPrimitive2,
  onExitIf: () => onExitIf2,
  onExitFilter: () => onExitFilter2,
  onExit: () => onExit2,
  onErrorIf: () => onErrorIf2,
  onErrorFilter: () => onErrorFilter2,
  onError: () => onError2,
  never: () => never2,
  matchEffect: () => matchEffect3,
  matchEager: () => matchEager2,
  matchCauseEffectEager: () => matchCauseEffectEager2,
  matchCauseEffect: () => matchCauseEffect2,
  matchCauseEager: () => matchCauseEager2,
  matchCause: () => matchCause2,
  match: () => match5,
  mapErrorEager: () => mapErrorEager2,
  mapError: () => mapError3,
  mapEager: () => mapEager2,
  mapBothEager: () => mapBothEager2,
  mapBoth: () => mapBoth2,
  map: () => map5,
  makeSpanScoped: () => makeSpanScoped2,
  makeSpan: () => makeSpan2,
  logWithLevel: () => logWithLevel2,
  logWarning: () => logWarning,
  logTrace: () => logTrace,
  logInfo: () => logInfo,
  logFatal: () => logFatal,
  logError: () => logError,
  logDebug: () => logDebug,
  log: () => log,
  linkSpans: () => linkSpans2,
  let: () => let_3,
  isSuccess: () => isSuccess5,
  isFailure: () => isFailure4,
  isEffect: () => isEffect2,
  interruptibleMask: () => interruptibleMask2,
  interruptible: () => interruptible2,
  interrupt: () => interrupt2,
  ignoreCause: () => ignoreCause2,
  ignore: () => ignore2,
  gen: () => gen2,
  fromYieldable: () => fromYieldable2,
  fromResult: () => fromResult2,
  fromOption: () => fromOption3,
  fromNullishOr: () => fromNullishOr2,
  forkScoped: () => forkScoped2,
  forkIn: () => forkIn2,
  forkDetach: () => forkDetach2,
  forkChild: () => forkChild2,
  forever: () => forever3,
  forEach: () => forEach2,
  fnUntracedEager: () => fnUntracedEager2,
  fnUntraced: () => fnUntraced2,
  fn: () => fn2,
  flip: () => flip2,
  flatten: () => flatten2,
  flatMapEager: () => flatMapEager2,
  flatMap: () => flatMap3,
  findFirstFilter: () => findFirstFilter2,
  findFirst: () => findFirst2,
  filterOrFail: () => filterOrFail2,
  filterOrElse: () => filterOrElse2,
  filterMapOrFail: () => filterMapOrFail2,
  filterMapOrElse: () => filterMapOrElse2,
  filterMapEffect: () => filterMapEffect2,
  filterMap: () => filterMap2,
  filter: () => filter5,
  fiberId: () => fiberId2,
  fiber: () => fiber2,
  failSync: () => failSync2,
  failCauseSync: () => failCauseSync2,
  failCause: () => failCause2,
  fail: () => fail5,
  exit: () => exit2,
  eventually: () => eventually2,
  ensuring: () => ensuring2,
  effectify: () => effectify,
  die: () => die2,
  delay: () => delay2,
  currentSpan: () => currentSpan2,
  currentParentSpan: () => currentParentSpan2,
  contextWith: () => contextWith2,
  context: () => context2,
  clockWith: () => clockWith2,
  catchTags: () => catchTags2,
  catchTag: () => catchTag3,
  catchReasons: () => catchReasons2,
  catchReason: () => catchReason2,
  catchNoSuchElement: () => catchNoSuchElement2,
  catchIf: () => catchIf2,
  catchFilter: () => catchFilter2,
  catchEager: () => catchEager2,
  catchDefect: () => catchDefect2,
  catchCauseIf: () => catchCauseIf2,
  catchCauseFilter: () => catchCauseFilter2,
  catchCause: () => catchCause3,
  catch: () => catch_3,
  callback: () => callback2,
  cachedWithTTL: () => cachedWithTTL2,
  cachedInvalidateWithTTL: () => cachedInvalidateWithTTL2,
  cached: () => cached2,
  bindTo: () => bindTo3,
  bind: () => bind3,
  awaitAllChildren: () => awaitAllChildren2,
  asVoid: () => asVoid2,
  asSome: () => asSome2,
  as: () => as2,
  annotateSpans: () => annotateSpans2,
  annotateLogsScoped: () => annotateLogsScoped2,
  annotateLogs: () => annotateLogs,
  annotateCurrentSpan: () => annotateCurrentSpan2,
  andThen: () => andThen2,
  all: () => all2,
  addFinalizer: () => addFinalizer2,
  acquireUseRelease: () => acquireUseRelease2,
  acquireRelease: () => acquireRelease2,
  abortSignal: () => abortSignal2,
  YieldableClass: () => YieldableClass,
  Transaction: () => Transaction,
  Do: () => Do2
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Exit.js
var fail4 = exitFail;
var void_2 = exitVoid;
var isSuccess4 = exitIsSuccess;
var getSuccess2 = exitGetSuccess;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Layer.js
var exports_Layer = {};
__export(exports_Layer, {
  withSpan: () => withSpan2,
  withParentSpan: () => withParentSpan2,
  updateService: () => updateService2,
  unwrap: () => unwrap,
  tapError: () => tapError2,
  tapCause: () => tapCause2,
  tap: () => tap2,
  syncContext: () => syncContext,
  sync: () => sync2,
  suspend: () => suspend2,
  succeedContext: () => succeedContext,
  succeed: () => succeed4,
  span: () => span,
  satisfiesSuccessType: () => satisfiesSuccessType,
  satisfiesServicesType: () => satisfiesServicesType,
  satisfiesErrorType: () => satisfiesErrorType,
  provideMerge: () => provideMerge,
  provide: () => provide2,
  parentSpan: () => parentSpan,
  orDie: () => orDie2,
  mock: () => mock,
  mergeAll: () => mergeAll2,
  merge: () => merge2,
  makeMemoMapUnsafe: () => makeMemoMapUnsafe,
  makeMemoMap: () => makeMemoMap,
  launch: () => launch,
  isLayer: () => isLayer,
  fromBuildMemo: () => fromBuildMemo,
  fromBuild: () => fromBuild,
  fresh: () => fresh,
  flatMap: () => flatMap2,
  empty: () => empty3,
  effectDiscard: () => effectDiscard,
  effectContext: () => effectContext,
  effect: () => effect,
  catchTag: () => catchTag2,
  catchCause: () => catchCause2,
  catch: () => catch_2,
  buildWithScope: () => buildWithScope,
  buildWithMemoMap: () => buildWithMemoMap,
  build: () => build,
  CurrentMemoMap: () => CurrentMemoMap
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Deferred.js
var TypeId5 = "~effect/Deferred";
var DeferredProto = {
  [TypeId5]: {
    _A: identity,
    _E: identity
  },
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var makeUnsafe2 = () => {
  const self = Object.create(DeferredProto);
  self.resumes = undefined;
  self.effect = undefined;
  return self;
};
var _await = (self) => callback((resume) => {
  if (self.effect)
    return resume(self.effect);
  self.resumes ??= [];
  self.resumes.push(resume);
  return sync(() => {
    const index = self.resumes.indexOf(resume);
    self.resumes.splice(index, 1);
  });
});
var completeWith = /* @__PURE__ */ dual(2, (self, effect) => sync(() => doneUnsafe(self, effect)));
var done3 = completeWith;
var doneUnsafe = (self, effect) => {
  if (self.effect)
    return false;
  self.effect = effect;
  if (self.resumes) {
    for (let i = 0;i < self.resumes.length; i++) {
      self.resumes[i](effect);
    }
    self.resumes = undefined;
  }
  return true;
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/References.js
var CurrentLogAnnotations2 = CurrentLogAnnotations;
var CurrentLogSpans2 = CurrentLogSpans;
var CurrentStackFrame2 = CurrentStackFrame;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Scope.js
var Scope = scopeTag;
var makeUnsafe3 = scopeMakeUnsafe;
var provide = provideScope;
var forkUnsafe2 = scopeForkUnsafe;
var close = scopeClose;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Layer.js
var TypeId6 = "~effect/Layer";
var MemoMapTypeId = "~effect/Layer/MemoMap";
var isLayer = (u) => hasProperty(u, TypeId6);
var LayerProto = {
  [TypeId6]: {
    _ROut: identity,
    _E: identity,
    _RIn: identity
  },
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var fromBuildUnsafe = (build) => {
  const self = Object.create(LayerProto);
  self.build = build;
  return self;
};
var fromBuild = (build) => fromBuildUnsafe((memoMap, scope2) => {
  const layerScope = forkUnsafe2(scope2);
  return onExit(build(memoMap, layerScope), (exit2) => exit2._tag === "Failure" ? close(layerScope, exit2) : void_);
});
var fromBuildMemo = (build) => {
  const self = fromBuild((memoMap, scope2) => memoMap.getOrElseMemoize(self, scope2, build));
  return self;
};

class MemoMapImpl {
  get [MemoMapTypeId]() {
    return MemoMapTypeId;
  }
  map = /* @__PURE__ */ new Map;
  getOrElseMemoize(layer, scope2, build) {
    if (this.map.has(layer)) {
      const entry2 = this.map.get(layer);
      entry2.observers++;
      return andThen(scopeAddFinalizerExit(scope2, (exit2) => entry2.finalizer(exit2)), entry2.effect);
    }
    const layerScope = makeUnsafe3();
    const deferred = makeUnsafe2();
    const entry = {
      observers: 1,
      effect: _await(deferred),
      finalizer: (exit2) => suspend(() => {
        entry.observers--;
        if (entry.observers === 0) {
          this.map.delete(layer);
          return close(layerScope, exit2);
        }
        return void_;
      })
    };
    this.map.set(layer, entry);
    return scopeAddFinalizerExit(scope2, entry.finalizer).pipe(flatMap(() => build(this, layerScope)), onExit((exit2) => {
      entry.effect = exit2;
      return done3(deferred, exit2);
    }));
  }
}
var makeMemoMapUnsafe = () => new MemoMapImpl;
var makeMemoMap = /* @__PURE__ */ sync(makeMemoMapUnsafe);

class CurrentMemoMap extends (/* @__PURE__ */ Service()("effect/Layer/CurrentMemoMap")) {
  static getOrCreate = /* @__PURE__ */ getOrElse2(this, makeMemoMapUnsafe);
}
var buildWithMemoMap = /* @__PURE__ */ dual(3, (self, memoMap, scope2) => provideService(map4(self.build(memoMap, scope2), add(CurrentMemoMap, memoMap)), CurrentMemoMap, memoMap));
var build = (self) => withFiber((fiber2) => buildWithMemoMap(self, CurrentMemoMap.getOrCreate(fiber2.context), getUnsafe2(fiber2.context, Scope)));
var buildWithScope = /* @__PURE__ */ dual(2, (self, scope2) => withFiber((fiber2) => buildWithMemoMap(self, CurrentMemoMap.getOrCreate(fiber2.context), scope2)));
var succeed4 = function() {
  if (arguments.length === 1) {
    return (resource) => succeedContext(make3(arguments[0], resource));
  }
  return succeedContext(make3(arguments[0], arguments[1]));
};
var succeedContext = (context2) => fromBuildUnsafe(constant(succeed3(context2)));
var empty3 = /* @__PURE__ */ succeedContext(/* @__PURE__ */ empty2());
var sync2 = function() {
  if (arguments.length === 1) {
    return (evaluate2) => syncContext(() => make3(arguments[0], evaluate2()));
  }
  return syncContext(() => make3(arguments[0], arguments[1]()));
};
var syncContext = (evaluate2) => fromBuildMemo(constant(sync(evaluate2)));
var effect = function() {
  if (arguments.length === 1) {
    return (effect2) => effectImpl(arguments[0], effect2);
  }
  return effectImpl(arguments[0], arguments[1]);
};
var effectImpl = (service2, effect2) => effectContext(map4(effect2, (value) => make3(service2, value)));
var effectContext = (effect2) => fromBuildMemo((_, scope2) => provide(effect2, scope2));
var effectDiscard = (effect2) => effectContext(as(effect2, empty2()));
var suspend2 = (evaluate2) => fromBuildMemo((memoMap, scope2) => suspend(() => evaluate2().build(memoMap, scope2)));
var unwrap = (self) => {
  const service2 = Service("effect/Layer/unwrap");
  return flatMap2(effect(service2)(self), get(service2));
};
var mergeAllEffect = (layers, memoMap, scope2) => {
  const parentScope = forkUnsafe2(scope2, "parallel");
  return forEach(layers, (layer) => layer.build(memoMap, forkUnsafe2(parentScope, "sequential")), {
    concurrency: layers.length
  }).pipe(map4((context2) => mergeAll(...context2)));
};
var mergeAll2 = (...layers) => fromBuild((memoMap, scope2) => mergeAllEffect(layers, memoMap, scope2));
var merge2 = /* @__PURE__ */ dual(2, (self, that) => mergeAll2(self, ...Array.isArray(that) ? that : [that]));
var provideWith = (self, that, f) => fromBuild((memoMap, scope2) => flatMap(Array.isArray(that) ? mergeAllEffect(that, memoMap, scope2) : that.build(memoMap, scope2), (context2) => self.build(memoMap, scope2).pipe(provideContext(context2), map4((merged) => f(merged, context2)))));
var provide2 = /* @__PURE__ */ dual(2, (self, that) => provideWith(self, that, identity));
var provideMerge = /* @__PURE__ */ dual(2, (self, that) => provideWith(self, that, (self2, that2) => merge(that2, self2)));
var flatMap2 = /* @__PURE__ */ dual(2, (self, f) => fromBuild((memoMap, scope2) => flatMap(self.build(memoMap, scope2), (context2) => f(context2).build(memoMap, scope2))));
var tap2 = /* @__PURE__ */ dual(2, (self, f) => fromBuild((memoMap, scope2) => flatMap(self.build(memoMap, scope2), (context2) => provide(as(f(context2), context2), scope2))));
var tapError2 = /* @__PURE__ */ dual(2, (self, f) => fromBuild((memoMap, scope2) => catch_(self.build(memoMap, scope2), (error) => provide(andThen(f(error), fail3(error)), scope2))));
var tapCause2 = /* @__PURE__ */ dual(2, (self, f) => fromBuild((memoMap, scope2) => catchCause(self.build(memoMap, scope2), (cause) => provide(andThen(f(cause), failCause(cause)), scope2))));
var orDie2 = (self) => fromBuildUnsafe((memoMap, scope2) => orDie(self.build(memoMap, scope2)));
var catch_2 = /* @__PURE__ */ dual(2, (self, onError2) => fromBuildUnsafe((memoMap, scope2) => catch_(self.build(memoMap, scope2), (e) => onError2(e).build(memoMap, scope2))));
var catchTag2 = /* @__PURE__ */ dual(3, (self, k, f) => fromBuildUnsafe((memoMap, scope2) => catchTag(self.build(memoMap, scope2), k, (error) => f(error).build(memoMap, scope2))));
var catchCause2 = /* @__PURE__ */ dual(2, (self, onError2) => fromBuildUnsafe((memoMap, scope2) => catchCause(self.build(memoMap, scope2), (cause) => onError2(cause).build(memoMap, scope2))));
var updateService2 = /* @__PURE__ */ dual(3, (layer, service2, f) => provide2(layer, effect(service2, map4(service2.asEffect(), f))));
var fresh = (self) => fromBuildUnsafe((_, scope2) => self.build(makeMemoMapUnsafe(), scope2));
var launch = (self) => scoped(andThen(build(self), never));
var mock = function() {
  if (arguments.length === 1) {
    return (implementation) => mockImpl(arguments[0], implementation);
  }
  return mockImpl(arguments[0], arguments[1]);
};
var mockImpl = (service2, implementation) => succeed4(service2)(new Proxy({
  ...implementation
}, {
  get(target, prop, _receiver) {
    if (prop in target) {
      return target[prop];
    }
    const prevLimit = Error.stackTraceLimit;
    Error.stackTraceLimit = 2;
    const error = new Error(`${service2.key}: Unimplemented method "${prop.toString()}"`);
    Error.stackTraceLimit = prevLimit;
    error.name = "UnimplementedError";
    return makeUnimplemented(error);
  },
  has: constTrue
}));
var makeUnimplemented = (error) => {
  const dead = Object.assign(die(error), {
    [StreamTypeId]: StreamTypeId,
    channel: {
      [ChannelTypeId]: ChannelTypeId,
      transform: () => succeed3(dead),
      pipe() {
        return pipeArguments(this, arguments);
      }
    },
    [ChannelTypeId]: ChannelTypeId,
    transform: () => succeed3(dead)
  });
  function unimplemented() {
    return dead;
  }
  Object.assign(unimplemented, dead);
  Object.setPrototypeOf(unimplemented, Object.getPrototypeOf(dead));
  return unimplemented;
};
var StreamTypeId = "~effect/Stream";
var ChannelTypeId = "~effect/Channel";
var satisfiesSuccessType = () => (layer) => layer;
var satisfiesErrorType = () => (layer) => layer;
var satisfiesServicesType = () => (layer) => layer;
var span = (name, options) => {
  options = addSpanStackTrace(options);
  return effect(ParentSpan, options?.onEnd ? tap(makeSpanScoped(name, options), (span2) => addFinalizer((exit2) => options.onEnd(span2, exit2))) : makeSpanScoped(name, options));
};
var parentSpan = (span2) => succeedContext(ParentSpan.context(span2));
var withSpan2 = function() {
  const dataFirst = typeof arguments[0] !== "string";
  const name = dataFirst ? arguments[1] : arguments[0];
  const options = addSpanStackTrace(dataFirst ? arguments[2] : arguments[1]);
  if (dataFirst) {
    const self = arguments[0];
    return unwrap(map4(options?.onEnd !== undefined ? tap(makeSpanScoped(name, options), (span2) => addFinalizer((exit2) => options.onEnd(span2, exit2))) : makeSpanScoped(name, options), (span2) => withParentSpan2(self, span2)));
  }
  return (self) => unwrap(map4(options?.onEnd !== undefined ? tap(makeSpanScoped(name, options), (span2) => addFinalizer((exit2) => options.onEnd(span2, exit2))) : makeSpanScoped(name, options), (span2) => withParentSpan2(self, span2)));
};
var withParentSpan2 = function() {
  const dataFirst = isLayer(arguments[0]);
  const span2 = dataFirst ? arguments[1] : arguments[0];
  let options = dataFirst ? arguments[2] : arguments[1];
  let provideStackFrame = identity;
  if (span2._tag === "Span") {
    options = addSpanStackTrace(options);
    provideStackFrame = provideSpanStackFrame2(span2.name, options?.captureStackTrace);
  }
  const parentSpanLayer = parentSpan(span2);
  if (dataFirst) {
    return provide2(provideStackFrame(arguments[0]), parentSpanLayer);
  }
  return (self) => provide2(provideStackFrame(self), parentSpanLayer);
};
var provideSpanStackFrame2 = (name, stack) => {
  stack = typeof stack === "function" ? stack : constUndefined;
  return updateService2(CurrentStackFrame2, (parent) => ({
    name,
    stack,
    parent
  }));
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/ExecutionPlan.js
var TypeId7 = "~effect/ExecutionPlan";
var Proto2 = {
  [TypeId7]: TypeId7,
  get withRequirements() {
    const self = this;
    return contextWith((context2) => succeed3(makeProto(self.steps.map((step) => ({
      ...step,
      provide: isLayer(step.provide) ? provide2(step.provide, succeedContext(context2)) : step.provide
    })))));
  },
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var makeProto = (steps) => {
  const self = Object.create(Proto2);
  self.steps = steps;
  return self;
};
var CurrentMetadata = /* @__PURE__ */ Reference("effect/ExecutionPlan/CurrentMetadata", {
  defaultValue: /* @__PURE__ */ constant({
    attempt: 0,
    stepIndex: 0
  })
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Pull.js
var catchDone = /* @__PURE__ */ dual(2, (effect2, f) => catchCauseFilter(effect2, filterDoneLeftover, (l) => f(l)));
var filterDone = /* @__PURE__ */ composePassthrough(findError2, (e) => isDone2(e) ? succeed2(e) : fail2(e));
var filterDoneLeftover = /* @__PURE__ */ composePassthrough(findError2, (e) => isDone2(e) ? succeed2(e.value) : fail2(e));
var matchEffect2 = /* @__PURE__ */ dual(2, (self, options) => matchCauseEffect(self, {
  onSuccess: options.onSuccess,
  onFailure: (cause) => {
    const halt = filterDone(cause);
    return !isFailure2(halt) ? options.onDone(halt.success.value) : options.onFailure(halt.failure);
  }
}));

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Schedule.js
var TypeId8 = "~effect/Schedule";
var CurrentMetadata2 = /* @__PURE__ */ Reference("effect/Schedule/CurrentMetadata", {
  defaultValue: /* @__PURE__ */ constant({
    input: undefined,
    output: undefined,
    duration: zero,
    attempt: 0,
    start: 0,
    now: 0,
    elapsed: 0,
    elapsedSincePrevious: 0
  })
});
var ScheduleProto = {
  [TypeId8]: {
    _Out: identity,
    _In: identity,
    _Env: identity
  },
  pipe() {
    return pipeArguments(this, arguments);
  }
};
var isSchedule = (u) => hasProperty(u, TypeId8);
var fromStep = (step) => {
  const self = Object.create(ScheduleProto);
  self.step = step;
  return self;
};
var metadataFn = () => {
  let n = 0;
  let previous;
  let start;
  return (now, input) => {
    if (start === undefined)
      start = now;
    const elapsed = now - start;
    const elapsedSincePrevious = previous === undefined ? 0 : now - previous;
    previous = now;
    return {
      input,
      attempt: ++n,
      start,
      now,
      elapsed,
      elapsedSincePrevious
    };
  };
};
var fromStepWithMetadata = (step) => fromStep(map4(step, (f) => {
  const meta = metadataFn();
  return (now, input) => f(meta(now, input));
}));
var toStep = (schedule) => catchCause(schedule.step, (cause) => succeed3(() => failCause(cause)));
var toStepWithMetadata = (schedule) => clockWith((clock) => map4(toStep(schedule), (step) => {
  const metaFn = metadataFn();
  return (input) => suspend(() => {
    const now = clock.currentTimeMillisUnsafe();
    return flatMap(step(now, input), ([output, duration]) => {
      const meta = metaFn(now, input);
      meta.output = output;
      meta.duration = duration;
      return as(sleep(duration), meta);
    });
  });
}));
var passthrough = (self) => fromStep(map4(toStep(self), (step) => (now, input) => matchEffect2(step(now, input), {
  onSuccess: (result2) => succeed3([input, result2[1]]),
  onFailure: failCause,
  onDone: () => done2(input)
})));
var recurs = (times) => while_(forever2, ({
  attempt
}) => succeed3(attempt <= times));
var spaced = (duration) => {
  const decoded = fromInputUnsafe(duration);
  return fromStepWithMetadata(succeed3((meta) => succeed3([meta.attempt - 1, decoded])));
};
var while_ = /* @__PURE__ */ dual(2, (self, predicate) => fromStep(map4(toStep(self), (step) => {
  const meta = metadataFn();
  return (now, input) => flatMap(step(now, input), (result2) => {
    const [output, duration] = result2;
    const eff = predicate({
      ...meta(now, input),
      output,
      duration
    });
    return flatMap(isEffect(eff) ? eff : succeed3(eff), (check) => check ? succeed3(result2) : done2(output));
  });
})));
var forever2 = /* @__PURE__ */ spaced(zero);

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/layer.js
var provideLayer = (self, layer, options) => scopedWith((scope2) => flatMap(options?.local ? buildWithMemoMap(layer, makeMemoMapUnsafe(), scope2) : buildWithScope(layer, scope2), (context2) => provideContext(self, context2)));
var provide3 = /* @__PURE__ */ dual((args2) => isEffect(args2[0]), (self, source, options) => isContext(source) ? provideContext(self, source) : provideLayer(self, Array.isArray(source) ? mergeAll2(...source) : source, options));

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/schedule.js
var repeatOrElse = /* @__PURE__ */ dual(3, (self, schedule, orElse) => flatMap(toStepWithMetadata(schedule), (step) => {
  let meta = CurrentMetadata2.defaultValue();
  return catch_(forever(tap(flatMap(suspend(() => provideService(self, CurrentMetadata2, meta)), step), (meta_) => sync(() => {
    meta = meta_;
  })), {
    disableYield: true
  }), (error) => isDone(error) ? succeed3(error.value) : orElse(error, meta.attempt === 0 ? none2() : some2(meta)));
}));
var retryOrElse = /* @__PURE__ */ dual(3, (self, policy, orElse) => flatMap(toStepWithMetadata(policy), (step) => {
  let meta = CurrentMetadata2.defaultValue();
  let lastError;
  const loop = catch_(suspend(() => provideService(self, CurrentMetadata2, meta)), (error) => {
    lastError = error;
    return flatMap(step(error), (meta_) => {
      meta = meta_;
      return loop;
    });
  });
  return catchDone(loop, (out) => internalCall(() => orElse(lastError, out)));
}));
var repeat = /* @__PURE__ */ dual(2, (self, options) => {
  const schedule = typeof options === "function" ? options(identity) : isSchedule(options) ? options : buildFromOptions(options);
  return repeatOrElse(self, schedule, fail3);
});
var retry = /* @__PURE__ */ dual(2, (self, options) => {
  const schedule = typeof options === "function" ? options(identity) : isSchedule(options) ? options : buildFromOptions(options);
  return retryOrElse(self, schedule, fail3);
});
var scheduleFrom = /* @__PURE__ */ dual(3, (self, initial, schedule) => flatMap(toStepWithMetadata(schedule), (step) => {
  let meta = CurrentMetadata2.defaultValue();
  const selfWithMeta = suspend(() => provideService(self, CurrentMetadata2, meta));
  return catch_(flatMap(step(initial), (meta_) => {
    meta = meta_;
    const body = constant(flatMap(selfWithMeta, step));
    return whileLoop({
      while: constTrue,
      body,
      step(meta_2) {
        meta = meta_2;
      }
    });
  }), (error) => isDone(error) ? succeed3(error.value) : fail3(error));
}));
var passthroughForever = /* @__PURE__ */ passthrough(forever2);
var buildFromOptions = (options) => {
  let schedule = options.schedule ? passthrough(options.schedule) : passthroughForever;
  if (options.while) {
    schedule = while_(schedule, ({
      input
    }) => {
      const applied = options.while(input);
      return isEffect(applied) ? applied : succeed3(applied);
    });
  }
  if (options.until) {
    schedule = while_(schedule, ({
      input
    }) => {
      const applied = options.until(input);
      return isEffect(applied) ? map4(applied, (b) => !b) : succeed3(!applied);
    });
  }
  if (options.times !== undefined) {
    schedule = while_(schedule, ({
      attempt
    }) => succeed3(attempt <= options.times));
  }
  return schedule;
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/executionPlan.js
var withExecutionPlan = /* @__PURE__ */ dual(2, (self, plan) => suspend(() => {
  let i = 0;
  let meta = {
    attempt: 0,
    stepIndex: 0
  };
  const provideMeta = provideServiceEffect(CurrentMetadata, sync(() => {
    meta = {
      attempt: meta.attempt + 1,
      stepIndex: i
    };
    return meta;
  }));
  let result2;
  return flatMap(whileLoop({
    while: () => i < plan.steps.length && (result2 === undefined || isFailure2(result2)),
    body() {
      const step = plan.steps[i];
      let nextEffect = provideMeta(provide3(self, step.provide));
      if (result2) {
        let attempted = false;
        const wrapped = nextEffect;
        nextEffect = suspend(() => {
          if (attempted)
            return wrapped;
          attempted = true;
          return result2.asEffect();
        });
        nextEffect = retry(nextEffect, scheduleFromStep(step, false));
      } else {
        const schedule = scheduleFromStep(step, true);
        nextEffect = schedule ? retry(nextEffect, schedule) : nextEffect;
      }
      return result(nextEffect);
    },
    step(result_) {
      result2 = result_;
      i++;
    }
  }), () => result2.asEffect());
}));
var scheduleFromStep = (step, first) => {
  if (!first) {
    return buildFromOptions({
      schedule: step.schedule ? step.schedule : step.attempts ? undefined : scheduleOnce,
      times: step.attempts,
      while: step.while
    });
  } else if (step.attempts === 1 || !(step.schedule || step.attempts)) {
    return;
  }
  return buildFromOptions({
    schedule: step.schedule,
    while: step.while,
    times: step.attempts ? step.attempts - 1 : undefined
  });
};
var scheduleOnce = /* @__PURE__ */ recurs(1);

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Request.js
var TypeId9 = "~effect/Request";
var requestVariance = /* @__PURE__ */ byReferenceUnsafe({
  _E: (_) => _,
  _A: (_) => _,
  _R: (_) => _
});
var RequestPrototype = {
  ...StructuralProto,
  [TypeId9]: requestVariance
};
var makeEntry = (options) => options;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/request.js
var request = /* @__PURE__ */ dual(2, (self, resolver) => {
  const withResolver = (resolver2) => callback((resume) => {
    const entry = addEntry(resolver2, self, resume, getCurrentFiber());
    return maybeRemoveEntry(resolver2, entry);
  });
  return isEffect(resolver) ? flatMap(resolver, withResolver) : withResolver(resolver);
});
var requestUnsafe = (self, options) => {
  const entry = addEntry(options.resolver, self, options.onExit, {
    context: options.context,
    currentScheduler: get(options.context, Scheduler)
  });
  return () => removeEntryUnsafe(options.resolver, entry);
};
var batchPool = [];
var pendingBatches = /* @__PURE__ */ new Map;
var addEntry = (resolver, request2, resume, fiber2) => {
  let batchMap = pendingBatches.get(resolver);
  if (!batchMap) {
    batchMap = new Map;
    pendingBatches.set(resolver, batchMap);
  }
  let batch;
  let completed = false;
  const entry = makeEntry({
    request: request2,
    context: fiber2.context,
    uninterruptible: false,
    completeUnsafe(effect2) {
      if (completed)
        return;
      completed = true;
      resume(effect2);
      batch?.entrySet.delete(entry);
    }
  });
  if (resolver.preCheck !== undefined && !resolver.preCheck(entry)) {
    return entry;
  }
  const key = resolver.batchKey(entry);
  batch = batchMap.get(key);
  if (!batch) {
    if (batchPool.length > 0) {
      batch = batchPool.pop();
      batch.key = key;
      batch.resolver = resolver;
      batch.map = batchMap;
    } else {
      const newBatch = {
        key,
        resolver,
        map: batchMap,
        entrySet: new Set,
        entries: new Set,
        delayEffect: flatMap(suspend(() => newBatch.resolver.delay), (_) => runBatch(newBatch)),
        run: onExit(suspend(() => newBatch.resolver.runAll(Array.from(newBatch.entries), newBatch.key)), (exit2) => {
          for (const entry2 of newBatch.entrySet) {
            entry2.completeUnsafe(exit2._tag === "Success" ? exitDie(new Error("Effect.request: RequestResolver did not complete request", {
              cause: entry2.request
            })) : exit2);
          }
          newBatch.entries.clear();
          if (batchPool.length < 128) {
            newBatch.entrySet.clear();
            newBatch.key = undefined;
            newBatch.fiber = undefined;
            batchPool.push(newBatch);
          }
          return void_;
        })
      };
      batch = newBatch;
    }
    batchMap.set(key, batch);
    batch.fiber = runForkWith(fiber2.context)(batch.delayEffect, {
      scheduler: fiber2.currentScheduler
    });
  }
  batch.entrySet.add(entry);
  batch.entries.add(entry);
  if (batch.resolver.collectWhile(batch.entries))
    return entry;
  batch.fiber.interruptUnsafe(fiber2.id);
  batch.fiber = runForkWith(fiber2.context)(runBatch(batch), {
    scheduler: fiber2.currentScheduler
  });
  return entry;
};
var removeEntryUnsafe = (resolver, entry) => {
  if (entry.uninterruptible)
    return;
  const batchMap = pendingBatches.get(resolver);
  if (!batchMap)
    return;
  const key = resolver.batchKey(entry.request);
  const batch = batchMap.get(key);
  if (!batch)
    return;
  batch.entries.delete(entry);
  batch.entrySet.delete(entry);
  if (batch.entries.size === 0) {
    batchMap.delete(key);
    batch.fiber?.interruptUnsafe();
  }
};
var maybeRemoveEntry = (resolver, entry) => sync(() => removeEntryUnsafe(resolver, entry));
function runBatch(batch) {
  if (!batch.map.has(batch.key))
    return void_;
  batch.map.delete(batch.key);
  return batch.run;
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Metric.js
var CurrentMetricAttributesKey = "effect/Metric/CurrentMetricAttributes";
var CurrentMetricAttributes = /* @__PURE__ */ Reference(CurrentMetricAttributesKey, {
  defaultValue: () => ({})
});
var MetricRegistryKey = "~effect/observability/Metric/MetricRegistryKey";
var MetricRegistry = /* @__PURE__ */ Reference(MetricRegistryKey, {
  defaultValue: () => new Map
});
var TypeId10 = "~effect/observability/Metric";

class Metric$ {
  [TypeId10] = TypeId10;
  #metadataCache = /* @__PURE__ */ new WeakMap;
  #metadata;
  id;
  description;
  attributes;
  constructor(id, description, attributes) {
    this.id = id;
    this.description = description;
    this.attributes = attributes;
  }
  valueUnsafe(context2) {
    return this.hook(context2).get(context2);
  }
  modifyUnsafe(input, context2) {
    return this.hook(context2).modify(input, context2);
  }
  updateUnsafe(input, context2) {
    return this.hook(context2).update(input, context2);
  }
  hook(context2) {
    const extraAttributes = get(context2, CurrentMetricAttributes);
    if (Object.keys(extraAttributes).length === 0) {
      if (isNotUndefined(this.#metadata)) {
        return this.#metadata.hooks;
      }
      this.#metadata = this.getOrCreate(context2, this.attributes);
      return this.#metadata.hooks;
    }
    const mergedAttributes = mergeAttributes(this.attributes, extraAttributes);
    let metadata = this.#metadataCache.get(mergedAttributes);
    if (isNotUndefined(metadata)) {
      return metadata.hooks;
    }
    metadata = this.getOrCreate(context2, mergedAttributes);
    this.#metadataCache.set(mergedAttributes, metadata);
    return metadata.hooks;
  }
  getOrCreate(context2, attributes) {
    const key = makeKey(this, attributes);
    const registry = get(context2, MetricRegistry);
    if (registry.has(key)) {
      return registry.get(key);
    }
    const hooks = this.createHooks();
    const meta = {
      id: this.id,
      type: this.type,
      description: this.description,
      attributes: attributesToRecord(attributes),
      hooks
    };
    registry.set(key, meta);
    return meta;
  }
  pipe() {
    return pipeArguments(this, arguments);
  }
}
var bigint03 = /* @__PURE__ */ BigInt(0);

class CounterMetric extends Metric$ {
  type = "Counter";
  #bigint;
  #incremental;
  constructor(id, options) {
    super(id, options?.description, attributesToRecord(options?.attributes));
    this.#bigint = options?.bigint ?? false;
    this.#incremental = options?.incremental ?? false;
  }
  createHooks() {
    let count = this.#bigint ? bigint03 : 0;
    const canUpdate = this.#incremental ? this.#bigint ? (value) => value >= bigint03 : (value) => value >= 0 : (_value) => true;
    const update = (value) => {
      if (canUpdate(value)) {
        count = count + value;
      }
    };
    return makeHooks(() => ({
      count,
      incremental: this.#incremental
    }), update);
  }
}

class GaugeMetric extends Metric$ {
  type = "Gauge";
  #bigint;
  constructor(id, options) {
    super(id, options?.description, attributesToRecord(options?.attributes));
    this.#bigint = options?.bigint ?? false;
  }
  createHooks() {
    let value = this.#bigint ? BigInt(0) : 0;
    const update = (input) => {
      value = input;
    };
    const modify = (input) => {
      value = value + input;
    };
    return makeHooks(() => ({
      value
    }), update, modify);
  }
}

class FrequencyMetric extends Metric$ {
  type = "Frequency";
  #preregisteredWords;
  constructor(id, options) {
    super(id, options?.description, attributesToRecord(options?.attributes));
    this.#preregisteredWords = options?.preregisteredWords;
  }
  createHooks() {
    const occurrences = new Map;
    if (isNotUndefined(this.#preregisteredWords)) {
      for (const word of this.#preregisteredWords) {
        occurrences.set(word, 0);
      }
    }
    const update = (word) => {
      const count = occurrences.get(word) ?? 0;
      occurrences.set(word, count + 1);
    };
    return makeHooks(() => ({
      occurrences
    }), update);
  }
}

class HistogramMetric extends Metric$ {
  type = "Histogram";
  #boundaries;
  constructor(id, options) {
    super(id, options?.description, attributesToRecord(options?.attributes));
    this.#boundaries = options.boundaries;
  }
  createHooks() {
    const bounds = this.#boundaries;
    const size = bounds.length;
    const values = new Uint32Array(size + 1);
    const boundaries = new Float64Array(size);
    let count = 0;
    let sum2 = 0;
    let min2 = Number.MAX_VALUE;
    let max2 = Number.MIN_VALUE;
    map3(sort(bounds, Number2), (n, i) => {
      boundaries[i] = n;
    });
    const update = (value) => {
      let from = 0;
      let to = size;
      while (from !== to) {
        const mid = Math.floor(from + (to - from) / 2);
        const boundary = boundaries[mid];
        if (value <= boundary) {
          to = mid;
        } else {
          from = mid;
        }
        if (to === from + 1) {
          if (value <= boundaries[from]) {
            to = from;
          } else {
            from = to;
          }
        }
      }
      values[from] = values[from] + 1;
      count = count + 1;
      sum2 = sum2 + value;
      if (value < min2) {
        min2 = value;
      }
      if (value > max2) {
        max2 = value;
      }
    };
    const getBuckets = () => {
      const builder = allocate(size);
      let cumulated = 0;
      for (let i = 0;i < size; i++) {
        const boundary = boundaries[i];
        const value = values[i];
        cumulated = cumulated + value;
        builder[i] = [boundary, cumulated];
      }
      return builder;
    };
    return makeHooks(() => ({
      buckets: getBuckets(),
      count,
      min: min2,
      max: max2,
      sum: sum2
    }), update);
  }
}

class SummaryMetric extends Metric$ {
  type = "Summary";
  #maxAge;
  #maxSize;
  #quantiles;
  constructor(id, options) {
    super(id, options?.description, attributesToRecord(options?.attributes));
    this.#maxAge = Math.max(toMillis(fromInputUnsafe(options.maxAge)), 0);
    this.#maxSize = options.maxSize;
    this.#quantiles = options.quantiles;
  }
  createHooks() {
    const sortedQuantiles = sort(this.#quantiles, Number2);
    const observations = allocate(this.#maxSize);
    for (const quantile of this.#quantiles) {
      if (quantile < 0 || quantile > 1) {
        throw new Error(`Quantile must be between 0 and 1, found: ${quantile}`);
      }
    }
    let head = 0;
    let count = 0;
    let sum2 = 0;
    let min2 = Number.MAX_VALUE;
    let max2 = Number.MIN_VALUE;
    const snapshot = (now) => {
      const builder = [];
      let i = 0;
      while (i < this.#maxSize) {
        const observation = observations[i];
        if (isNotUndefined(observation)) {
          const [timestamp, value] = observation;
          const age = now - timestamp;
          if (age >= 0 && age <= this.#maxAge) {
            builder.push(value);
          }
        }
        i = i + 1;
      }
      const samples = sort(builder, Number2);
      const sampleSize = samples.length;
      if (sampleSize === 0) {
        return sortedQuantiles.map((q) => [q, undefined]);
      }
      return sortedQuantiles.map((q) => {
        if (q <= 0)
          return [q, samples[0]];
        if (q >= 1)
          return [q, samples[sampleSize - 1]];
        const index = Math.ceil(q * sampleSize) - 1;
        return [q, samples[index]];
      });
    };
    const observe = (value, timestamp) => {
      if (this.#maxSize > 0) {
        const target = head % this.#maxSize;
        observations[target] = [timestamp, value];
        head = head + 1;
      }
      count = count + 1;
      sum2 = sum2 + value;
      if (value < min2) {
        min2 = value;
      }
      if (value > max2) {
        max2 = value;
      }
    };
    const get2 = (context2) => {
      const clock = get(context2, ClockRef);
      const quantiles = snapshot(clock.currentTimeMillisUnsafe());
      return {
        quantiles,
        count,
        min: min2,
        max: max2,
        sum: sum2
      };
    };
    const update = ([value, timestamp]) => observe(value, timestamp);
    return makeHooks(get2, update);
  }
}
var update = /* @__PURE__ */ dual(2, (self, input) => contextWith((services) => sync(() => self.updateUnsafe(input, services))));
function makeKey(metric, attributes) {
  let key = `${metric.type}:${metric.id}`;
  if (isNotUndefined(metric.description)) {
    key += `:${metric.description}`;
  }
  if (isNotUndefined(attributes)) {
    key += `:${serializeAttributes(attributes)}`;
  }
  return key;
}
function makeHooks(get2, update2, modify) {
  return {
    get: get2,
    update: update2,
    modify: modify ?? update2
  };
}
function serializeAttributes(attributes) {
  return serializeEntries(Array.isArray(attributes) ? attributes : Object.entries(attributes));
}
function serializeEntries(entries) {
  return entries.map(([key, value]) => `${key}=${value}`).join(",");
}
function mergeAttributes(self, other) {
  return {
    ...attributesToRecord(self),
    ...attributesToRecord(other)
  };
}
function attributesToRecord(attributes) {
  if (isNotUndefined(attributes) && Array.isArray(attributes)) {
    return attributes.reduce((acc, [key, value]) => {
      acc[key] = value;
      return acc;
    }, {});
  }
  return attributes;
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Effect.js
class YieldableClass {
  [Symbol.iterator]() {
    return new SingleShotGen(this);
  }
}
var isEffect2 = isEffect;
var all2 = all;
var partition3 = partition2;
var validate2 = validate;
var findFirst2 = findFirst;
var findFirstFilter2 = findFirstFilter;
var forEach2 = forEach;
var whileLoop2 = whileLoop;
var promise2 = promise;
var tryPromise2 = tryPromise;
var succeed5 = succeed3;
var succeedNone2 = succeedNone;
var succeedSome2 = succeedSome;
var suspend3 = suspend;
var sync3 = sync;
var void_3 = void_;
var undefined_2 = undefined_;
var callback2 = callback;
var never2 = never;
var Do2 = Do;
var bindTo3 = bindTo2;
var let_3 = let_2;
var bind3 = bind2;
var gen2 = gen;
var fail5 = fail3;
var failSync2 = failSync;
var failCause2 = failCause;
var failCauseSync2 = failCauseSync;
var die2 = die;
var try_2 = try_;
var yieldNow2 = yieldNow;
var yieldNowWith2 = yieldNowWith;
var withFiber2 = withFiber;
var fromResult2 = fromResult;
var fromOption3 = fromOption2;
var fromNullishOr2 = fromNullishOr;
var fromYieldable2 = fromYieldable;
var flatMap3 = flatMap;
var flatten2 = flatten;
var andThen2 = andThen;
var tap3 = tap;
var result2 = result;
var option2 = option;
var exit2 = exit;
var map5 = map4;
var as2 = as;
var asSome2 = asSome;
var asVoid2 = asVoid;
var flip2 = flip;
var zip2 = zip;
var zipWith2 = zipWith;
var catch_3 = catch_;
var catchTag3 = catchTag;
var catchTags2 = catchTags;
var catchReason2 = catchReason;
var catchReasons2 = catchReasons;
var unwrapReason2 = unwrapReason;
var catchCause3 = catchCause;
var catchDefect2 = catchDefect;
var catchIf2 = catchIf;
var catchFilter2 = catchFilter;
var catchNoSuchElement2 = catchNoSuchElement;
var catchCauseIf2 = catchCauseIf;
var catchCauseFilter2 = catchCauseFilter;
var mapError3 = mapError2;
var mapBoth2 = mapBoth;
var orDie3 = orDie;
var tapError3 = tapError;
var tapErrorTag2 = tapErrorTag;
var tapCause3 = tapCause;
var tapCauseIf2 = tapCauseIf;
var tapCauseFilter2 = tapCauseFilter;
var tapDefect2 = tapDefect;
var eventually2 = eventually;
var retry2 = retry;
var retryOrElse2 = retryOrElse;
var sandbox2 = sandbox;
var ignore2 = ignore;
var ignoreCause2 = ignoreCause;
var withExecutionPlan2 = withExecutionPlan;
var withErrorReporting2 = withErrorReporting;
var orElseSucceed2 = orElseSucceed;
var timeout2 = timeout;
var timeoutOption2 = timeoutOption;
var timeoutOrElse2 = timeoutOrElse;
var delay2 = delay;
var sleep2 = sleep;
var timed2 = timed;
var raceAll2 = raceAll;
var raceAllFirst2 = raceAllFirst;
var race2 = race;
var raceFirst2 = raceFirst;
var filter5 = filter3;
var filterMap2 = filterMap;
var filterMapEffect2 = filterMapEffect;
var filterOrElse2 = filterOrElse;
var filterMapOrElse2 = filterMapOrElse;
var filterOrFail2 = filterOrFail;
var filterMapOrFail2 = filterMapOrFail;
var when2 = when;
var match5 = match4;
var matchEager2 = matchEager;
var matchCause2 = matchCause;
var matchCauseEager2 = matchCauseEager;
var matchCauseEffectEager2 = matchCauseEffectEager;
var matchCauseEffect2 = matchCauseEffect;
var matchEffect3 = matchEffect;
var isFailure4 = isFailure3;
var isSuccess5 = isSuccess3;
var context2 = context;
var contextWith2 = contextWith;
var provide4 = provide3;
var provideContext2 = provideContext;
var service2 = service;
var serviceOption2 = serviceOption;
var updateContext2 = updateContext;
var updateService3 = updateService;
var provideService2 = provideService;
var provideServiceEffect2 = provideServiceEffect;
var withConcurrency2 = withConcurrency;
var scope2 = scope;
var scoped2 = scoped;
var scopedWith2 = scopedWith;
var acquireRelease2 = acquireRelease;
var acquireUseRelease2 = acquireUseRelease;
var addFinalizer2 = addFinalizer;
var ensuring2 = ensuring;
var onError2 = onError;
var onErrorIf2 = onErrorIf;
var onErrorFilter2 = onErrorFilter;
var onExitPrimitive2 = onExitPrimitive;
var onExit2 = onExit;
var onExitIf2 = onExitIf;
var onExitFilter2 = onExitFilter;
var cached2 = cached;
var cachedWithTTL2 = cachedWithTTL;
var cachedInvalidateWithTTL2 = cachedInvalidateWithTTL;
var interrupt2 = interrupt;
var interruptible2 = interruptible;
var onInterrupt2 = onInterrupt;
var uninterruptible2 = uninterruptible;
var uninterruptibleMask2 = uninterruptibleMask;
var interruptibleMask2 = interruptibleMask;
var abortSignal2 = abortSignal;
var forever3 = forever;
var repeat2 = repeat;
var repeatOrElse2 = repeatOrElse;
var replicate2 = replicate;
var replicateEffect2 = replicateEffect;
var schedule = /* @__PURE__ */ dual(2, (self, schedule2) => scheduleFrom2(self, undefined, schedule2));
var scheduleFrom2 = scheduleFrom;
var tracer2 = tracer;
var withTracer2 = withTracer;
var withTracerEnabled2 = withTracerEnabled;
var withTracerTiming2 = withTracerTiming;
var annotateSpans2 = annotateSpans;
var annotateCurrentSpan2 = annotateCurrentSpan;
var currentSpan2 = currentSpan;
var currentParentSpan2 = currentParentSpan;
var spanAnnotations2 = spanAnnotations;
var spanLinks2 = spanLinks;
var linkSpans2 = linkSpans;
var makeSpan2 = makeSpan;
var makeSpanScoped2 = makeSpanScoped;
var useSpan2 = useSpan;
var withSpan3 = withSpan;
var withSpanScoped2 = withSpanScoped;
var withParentSpan3 = withParentSpan;
var request2 = request;
var requestUnsafe2 = requestUnsafe;
var forkChild2 = forkChild;
var forkIn2 = forkIn;
var forkScoped2 = forkScoped;
var forkDetach2 = forkDetach;
var awaitAllChildren2 = awaitAllChildren;
var fiber2 = fiber;
var fiberId2 = fiberId;
var runFork2 = runFork;
var runForkWith2 = runForkWith;
var runCallbackWith2 = runCallbackWith;
var runCallback2 = runCallback;
var runPromise2 = runPromise;
var runPromiseWith2 = runPromiseWith;
var runPromiseExit2 = runPromiseExit;
var runPromiseExitWith2 = runPromiseExitWith;
var runSync2 = runSync;
var runSyncWith2 = runSyncWith;
var runSyncExit2 = runSyncExit;
var runSyncExitWith2 = runSyncExitWith;
var fnUntraced2 = fnUntraced;
var fn2 = fn;
var clockWith2 = clockWith;
var logWithLevel2 = logWithLevel;
var log = /* @__PURE__ */ logWithLevel();
var logFatal = /* @__PURE__ */ logWithLevel("Fatal");
var logWarning = /* @__PURE__ */ logWithLevel("Warn");
var logError = /* @__PURE__ */ logWithLevel("Error");
var logInfo = /* @__PURE__ */ logWithLevel("Info");
var logDebug = /* @__PURE__ */ logWithLevel("Debug");
var logTrace = /* @__PURE__ */ logWithLevel("Trace");
var withLogger = /* @__PURE__ */ dual(2, (effect2, logger) => updateService(effect2, CurrentLoggers, (loggers) => new Set([...loggers, logger])));
var annotateLogs = /* @__PURE__ */ dual((args2) => isEffect2(args2[0]), (effect2, ...args2) => updateService(effect2, CurrentLogAnnotations2, (annotations) => {
  const newAnnotations = {
    ...annotations
  };
  if (args2.length === 1) {
    Object.assign(newAnnotations, args2[0]);
  } else {
    newAnnotations[args2[0]] = args2[1];
  }
  return newAnnotations;
}));
var annotateLogsScoped2 = annotateLogsScoped;
var withLogSpan = /* @__PURE__ */ dual(2, (effect2, label) => flatMap(currentTimeMillis, (now) => updateService(effect2, CurrentLogSpans2, (spans) => {
  const span2 = [label, now];
  return [span2, ...spans];
})));
var track = /* @__PURE__ */ dual((args2) => isEffect2(args2[0]), (self, metric, f) => onExit2(self, (exit3) => {
  const input = f === undefined ? exit3 : internalCall(() => f(exit3));
  return update(metric, input);
}));
var trackSuccesses = /* @__PURE__ */ dual((args2) => isEffect2(args2[0]), (self, metric, f) => tap3(self, (value) => {
  const input = f === undefined ? value : f(value);
  return update(metric, input);
}));
var trackErrors = /* @__PURE__ */ dual((args2) => isEffect2(args2[0]), (self, metric, f) => tapError3(self, (error) => {
  const input = f === undefined ? error : internalCall(() => f(error));
  return update(metric, input);
}));
var trackDefects = /* @__PURE__ */ dual((args2) => isEffect2(args2[0]), (self, metric, f) => tapDefect2(self, (defect) => {
  const input = f === undefined ? defect : internalCall(() => f(defect));
  return update(metric, input);
}));
var trackDuration = /* @__PURE__ */ dual((args2) => isEffect2(args2[0]), (self, metric, f) => clockWith2((clock) => {
  const startTime = clock.currentTimeNanosUnsafe();
  return onExit2(self, () => {
    const endTime = clock.currentTimeNanosUnsafe();
    const duration = subtract(fromInputUnsafe(endTime), fromInputUnsafe(startTime));
    const input = f === undefined ? duration : internalCall(() => f(duration));
    return update(metric, input);
  });
}));

class Transaction extends (/* @__PURE__ */ Service()("effect/Effect/Transaction")) {
}
var tx = (effect2) => withFiber2((fiber3) => {
  if (fiber3.context.mapUnsafe.has(Transaction.key)) {
    return effect2;
  }
  const state = {
    journal: new Map,
    retry: false
  };
  let result3;
  return uninterruptibleMask2((restore) => flatMap3(whileLoop2({
    while: () => !result3,
    body: constant(restore(effect2).pipe(provideService2(Transaction, state), tapCause3(() => {
      if (!state.retry)
        return void_3;
      return restore(awaitPendingTransaction(state));
    }), exit2)),
    step(exit3) {
      if (state.retry || !isTransactionConsistent(state)) {
        return clearTransaction(state);
      }
      if (isSuccess4(exit3)) {
        commitTransaction(fiber3, state);
      } else {
        clearTransaction(state);
      }
      result3 = exit3;
    }
  }), () => result3));
});
var isTransactionConsistent = (state) => {
  for (const [ref, {
    version: version2
  }] of state.journal) {
    if (ref.version !== version2) {
      return false;
    }
  }
  return true;
};
var awaitPendingTransaction = (state) => suspend3(() => {
  const key = {};
  const refs = Array.from(state.journal.keys());
  const clearPending = () => {
    for (const clear of refs) {
      clear.pending.delete(key);
    }
  };
  return callback2((resume) => {
    const onCall = () => {
      clearPending();
      resume(void_3);
    };
    for (const ref of refs) {
      ref.pending.set(key, onCall);
    }
    return sync3(clearPending);
  });
});
function commitTransaction(fiber3, state) {
  for (const [ref, {
    value
  }] of state.journal) {
    if (value !== ref.value) {
      ref.version = ref.version + 1;
      ref.value = value;
    }
    for (const pending of ref.pending.values()) {
      fiber3.currentDispatcher.scheduleTask(pending, 0);
    }
    ref.pending.clear();
  }
}
function clearTransaction(state) {
  state.retry = false;
  state.journal.clear();
}
var txRetry = /* @__PURE__ */ flatMap3(/* @__PURE__ */ Transaction.asEffect(), (state) => {
  state.retry = true;
  return interrupt2;
});
var effectify = (fn3, onError3, onSyncError) => (...args2) => callback2((resume) => {
  try {
    fn3(...args2, (err, result3) => {
      if (err) {
        resume(fail5(onError3 ? onError3(err, args2) : err));
      } else {
        resume(succeed5(result3));
      }
    });
  } catch (err) {
    resume(onSyncError ? fail5(onSyncError(err, args2)) : die2(err));
  }
});
var satisfiesSuccessType2 = () => (effect2) => effect2;
var satisfiesErrorType2 = () => (effect2) => effect2;
var satisfiesServicesType2 = () => (effect2) => effect2;
var mapEager2 = mapEager;
var mapErrorEager2 = mapErrorEager;
var mapBothEager2 = mapBothEager;
var flatMapEager2 = flatMapEager;
var catchEager2 = catchEager;
var fnUntracedEager2 = fnUntracedEager;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Encoding.js
var EncodingErrorTypeId = "~effect/encoding/EncodingError";

class EncodingError extends (/* @__PURE__ */ TaggedError2("EncodingError")) {
  [EncodingErrorTypeId] = EncodingErrorTypeId;
}
var encodeBase64 = (input) => typeof input === "string" ? base64EncodeUint8Array(encoder.encode(input)) : base64EncodeUint8Array(input);
var decodeBase64 = (str) => {
  const stripped = stripCrlf(str);
  const length = stripped.length;
  if (length % 4 !== 0) {
    return fail2(new EncodingError({
      kind: "Decode",
      module: "Base64",
      input: stripped,
      message: `Length must be a multiple of 4, but is ${length}`
    }));
  }
  const index = stripped.indexOf("=");
  if (index !== -1 && (index < length - 2 || index === length - 2 && stripped[length - 1] !== "=")) {
    return fail2(new EncodingError({
      kind: "Decode",
      module: "Base64",
      input: stripped,
      message: `Found a '=' character, but it is not at the end`
    }));
  }
  try {
    const missingOctets = stripped.endsWith("==") ? 2 : stripped.endsWith("=") ? 1 : 0;
    const result3 = new Uint8Array(3 * (length / 4) - missingOctets);
    for (let i = 0, j = 0;i < length; i += 4, j += 3) {
      const buffer = getBase64Code(stripped.charCodeAt(i)) << 18 | getBase64Code(stripped.charCodeAt(i + 1)) << 12 | getBase64Code(stripped.charCodeAt(i + 2)) << 6 | getBase64Code(stripped.charCodeAt(i + 3));
      result3[j] = buffer >> 16;
      result3[j + 1] = buffer >> 8 & 255;
      result3[j + 2] = buffer & 255;
    }
    return succeed2(result3);
  } catch (e) {
    return fail2(new EncodingError({
      kind: "Decode",
      module: "Base64",
      input: stripped,
      message: e instanceof Error ? e.message : "Invalid input"
    }));
  }
};
var encoder = /* @__PURE__ */ new TextEncoder;
var stripCrlf = (str) => str.replace(/[\n\r]/g, "");
var base64EncodeUint8Array = (bytes) => {
  const length = bytes.length;
  let result3 = "";
  let i;
  for (i = 2;i < length; i += 3) {
    result3 += base64abc[bytes[i - 2] >> 2];
    result3 += base64abc[(bytes[i - 2] & 3) << 4 | bytes[i - 1] >> 4];
    result3 += base64abc[(bytes[i - 1] & 15) << 2 | bytes[i] >> 6];
    result3 += base64abc[bytes[i] & 63];
  }
  if (i === length + 1) {
    result3 += base64abc[bytes[i - 2] >> 2];
    result3 += base64abc[(bytes[i - 2] & 3) << 4];
    result3 += "==";
  }
  if (i === length) {
    result3 += base64abc[bytes[i - 2] >> 2];
    result3 += base64abc[(bytes[i - 2] & 3) << 4 | bytes[i - 1] >> 4];
    result3 += base64abc[(bytes[i - 1] & 15) << 2];
    result3 += "=";
  }
  return result3;
};
function getBase64Code(charCode) {
  if (charCode >= base64codes.length) {
    throw new TypeError(`Invalid character ${String.fromCharCode(charCode)}`);
  }
  const code = base64codes[charCode];
  if (code === 255) {
    throw new TypeError(`Invalid character ${String.fromCharCode(charCode)}`);
  }
  return code;
}
var base64abc = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "/"];
var base64codes = [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 62, 255, 255, 255, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 255, 255, 255, 0, 255, 255, 255, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 255, 255, 255, 255, 255, 255, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51];

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/schema/annotations.js
function resolve(ast) {
  return ast.checks ? ast.checks[ast.checks.length - 1].annotations : ast.annotations;
}
function resolveAt(key) {
  return (ast) => resolve(ast)?.[key];
}
var resolveIdentifier = /* @__PURE__ */ resolveAt("identifier");
var getExpected = /* @__PURE__ */ memoize((ast) => {
  const identifier2 = resolveIdentifier(ast);
  if (typeof identifier2 === "string")
    return identifier2;
  return ast.getExpected(getExpected);
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/record.js
function set(self, key, value) {
  if (key === "__proto__") {
    Object.defineProperty(self, key, {
      value,
      writable: true,
      enumerable: true,
      configurable: true
    });
  } else {
    self[key] = value;
  }
  return self;
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/RegExp.js
var RegExp2 = globalThis.RegExp;
var escape = (string2) => string2.replace(/[/\\^$*+?.()|[\]{}]/g, "\\$&");

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/redacted.js
var redactedRegistry = /* @__PURE__ */ new WeakMap;
var value = (self) => {
  if (redactedRegistry.has(self)) {
    return redactedRegistry.get(self);
  } else {
    throw new Error("Unable to get redacted value" + (self.label ? ` with label: "${self.label}"` : ""));
  }
};

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Redacted.js
var TypeId11 = "~effect/data/Redacted";
var isRedacted = (u) => hasProperty(u, TypeId11);
var make6 = (value2, options) => {
  const self = Object.create(Proto3);
  if (options?.label) {
    self.label = options.label;
  }
  redactedRegistry.set(self, value2);
  return self;
};
var Proto3 = {
  [TypeId11]: {
    _A: (_) => _
  },
  label: undefined,
  ...PipeInspectableProto,
  toJSON() {
    return this.toString();
  },
  toString() {
    return `<redacted${isString(this.label) ? ":" + this.label : ""}>`;
  },
  [symbol]() {
    return hash(redactedRegistry.get(this));
  },
  [symbol2](that) {
    return isRedacted(that) && equals(redactedRegistry.get(this), redactedRegistry.get(that));
  }
};
var value2 = value;
var makeEquivalence = (isEquivalent) => make((x, y) => isEquivalent(value2(x), value2(y)));

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/SchemaIssue.js
var TypeId12 = "~effect/SchemaIssue/Issue";
function isIssue(u) {
  return hasProperty(u, TypeId12);
}

class Base {
  [TypeId12] = TypeId12;
  toString() {
    return defaultFormatter(this);
  }
}

class Filter extends Base {
  _tag = "Filter";
  actual;
  filter;
  issue;
  constructor(actual, filter6, issue) {
    super();
    this.actual = actual;
    this.filter = filter6;
    this.issue = issue;
  }
}

class Encoding extends Base {
  _tag = "Encoding";
  ast;
  actual;
  issue;
  constructor(ast, actual, issue) {
    super();
    this.ast = ast;
    this.actual = actual;
    this.issue = issue;
  }
}

class Pointer extends Base {
  _tag = "Pointer";
  path;
  issue;
  constructor(path, issue) {
    super();
    this.path = path;
    this.issue = issue;
  }
}

class MissingKey extends Base {
  _tag = "MissingKey";
  annotations;
  constructor(annotations) {
    super();
    this.annotations = annotations;
  }
}

class UnexpectedKey extends Base {
  _tag = "UnexpectedKey";
  ast;
  actual;
  constructor(ast, actual) {
    super();
    this.ast = ast;
    this.actual = actual;
  }
}

class Composite extends Base {
  _tag = "Composite";
  ast;
  actual;
  issues;
  constructor(ast, actual, issues) {
    super();
    this.ast = ast;
    this.actual = actual;
    this.issues = issues;
  }
}

class InvalidType extends Base {
  _tag = "InvalidType";
  ast;
  actual;
  constructor(ast, actual) {
    super();
    this.ast = ast;
    this.actual = actual;
  }
}

class InvalidValue extends Base {
  _tag = "InvalidValue";
  actual;
  annotations;
  constructor(actual, annotations) {
    super();
    this.actual = actual;
    this.annotations = annotations;
  }
}

class Forbidden extends Base {
  _tag = "Forbidden";
  actual;
  annotations;
  constructor(actual, annotations) {
    super();
    this.actual = actual;
    this.annotations = annotations;
  }
}

class AnyOf extends Base {
  _tag = "AnyOf";
  ast;
  actual;
  issues;
  constructor(ast, actual, issues) {
    super();
    this.ast = ast;
    this.actual = actual;
    this.issues = issues;
  }
}

class OneOf extends Base {
  _tag = "OneOf";
  ast;
  actual;
  successes;
  constructor(ast, actual, successes) {
    super();
    this.ast = ast;
    this.actual = actual;
    this.successes = successes;
  }
}
function makeFilterIssue(input, entry) {
  if (isIssue(entry)) {
    return entry;
  }
  if (typeof entry === "string") {
    return new InvalidValue(some2(input), {
      message: entry
    });
  }
  const inner = typeof entry.issue === "string" ? new InvalidValue(some2(input), {
    message: entry.issue
  }) : entry.issue;
  return new Pointer(entry.path, inner);
}
function makeSingle(input, out) {
  if (out === undefined) {
    return;
  }
  if (typeof out === "boolean") {
    return out ? undefined : new InvalidValue(some2(input));
  }
  return makeFilterIssue(input, out);
}
function make7(input, ast, out) {
  if (Array.isArray(out)) {
    if (isReadonlyArrayNonEmpty(out)) {
      if (out.length === 1) {
        return makeFilterIssue(input, out[0]);
      }
      return new Composite(ast, some2(input), map3(out, (entry) => makeFilterIssue(input, entry)));
    }
    return;
  }
  return makeSingle(input, out);
}
var defaultLeafHook = (issue) => {
  const message = findMessage(issue);
  if (message !== undefined)
    return message;
  switch (issue._tag) {
    case "InvalidType":
      return getExpectedMessage(getExpected(issue.ast), formatOption(issue.actual));
    case "InvalidValue":
      return `Invalid data ${formatOption(issue.actual)}`;
    case "MissingKey":
      return "Missing key";
    case "UnexpectedKey":
      return `Unexpected key with value ${format(issue.actual)}`;
    case "Forbidden":
      return "Forbidden operation";
    case "OneOf":
      return `Expected exactly one member to match the input ${format(issue.actual)}`;
  }
};
var defaultCheckHook = (issue) => {
  return findMessage(issue.issue) ?? findMessage(issue);
};
function getExpectedMessage(expected, actual) {
  return `Expected ${expected}, got ${actual}`;
}
function toDefaultIssues(issue, path, leafHook, checkHook) {
  switch (issue._tag) {
    case "Filter": {
      const message = checkHook(issue);
      if (message !== undefined) {
        return [{
          path,
          message
        }];
      }
      switch (issue.issue._tag) {
        case "InvalidValue":
          return [{
            path,
            message: getExpectedMessage(formatCheck(issue.filter), format(issue.actual))
          }];
        default:
          return toDefaultIssues(issue.issue, path, leafHook, checkHook);
      }
    }
    case "Encoding":
      return toDefaultIssues(issue.issue, path, leafHook, checkHook);
    case "Pointer":
      return toDefaultIssues(issue.issue, [...path, ...issue.path], leafHook, checkHook);
    case "Composite":
      return issue.issues.flatMap((issue2) => toDefaultIssues(issue2, path, leafHook, checkHook));
    case "AnyOf": {
      const message = findMessage(issue);
      if (issue.issues.length === 0) {
        if (message !== undefined)
          return [{
            path,
            message
          }];
        const expected = getExpectedMessage(getExpected(issue.ast), format(issue.actual));
        return [{
          path,
          message: expected
        }];
      }
      return issue.issues.flatMap((issue2) => toDefaultIssues(issue2, path, leafHook, checkHook));
    }
    default:
      return [{
        path,
        message: leafHook(issue)
      }];
  }
}
function formatCheck(check) {
  const expected = check.annotations?.expected;
  if (typeof expected === "string")
    return expected;
  switch (check._tag) {
    case "Filter":
      return "<filter>";
    case "FilterGroup":
      return check.checks.map((check2) => formatCheck(check2)).join(" & ");
  }
}
function makeFormatterDefault() {
  return (issue) => toDefaultIssues(issue, [], defaultLeafHook, defaultCheckHook).map(formatDefaultIssue).join(`
`);
}
var defaultFormatter = /* @__PURE__ */ makeFormatterDefault();
function formatDefaultIssue(issue) {
  let out = issue.message;
  if (issue.path && issue.path.length > 0) {
    const path = formatPath(issue.path);
    out += `
  at ${path}`;
  }
  return out;
}
function findMessage(issue) {
  switch (issue._tag) {
    case "InvalidType":
    case "OneOf":
    case "Composite":
    case "AnyOf":
      return getMessageAnnotation(issue.ast.annotations);
    case "InvalidValue":
    case "Forbidden":
      return getMessageAnnotation(issue.annotations);
    case "MissingKey":
      return getMessageAnnotation(issue.annotations, "messageMissingKey");
    case "UnexpectedKey":
      return getMessageAnnotation(issue.ast.annotations, "messageUnexpectedKey");
    case "Filter":
      return getMessageAnnotation(issue.filter.annotations);
    case "Encoding":
      return findMessage(issue.issue);
  }
}
function getMessageAnnotation(annotations, type = "message") {
  const message = annotations?.[type];
  if (typeof message === "string")
    return message;
}
function formatOption(actual) {
  if (isNone2(actual))
    return "no value provided";
  return format(actual.value);
}
function redact2(issue) {
  switch (issue._tag) {
    case "MissingKey":
      return issue;
    case "Forbidden":
      return new Forbidden(map(issue.actual, make6), issue.annotations);
    case "Filter":
      return new Filter(make6(issue.actual), issue.filter, redact2(issue.issue));
    case "Pointer":
      return new Pointer(issue.path, redact2(issue.issue));
    case "Encoding":
    case "InvalidType":
    case "InvalidValue":
    case "Composite":
      return new InvalidValue(map(issue.actual, make6));
    case "AnyOf":
    case "OneOf":
    case "UnexpectedKey":
      return new InvalidValue(some2(make6(issue.actual)));
  }
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/SchemaGetter.js
class Getter extends Class {
  run;
  constructor(run) {
    super();
    this.run = run;
  }
  map(f) {
    return new Getter((oe, options) => this.run(oe, options).pipe(mapEager2(map(f))));
  }
  compose(other) {
    if (isPassthrough(this)) {
      return other;
    }
    if (isPassthrough(other)) {
      return this;
    }
    return new Getter((oe, options) => this.run(oe, options).pipe(flatMapEager2((ot) => other.run(ot, options))));
  }
}
function fail6(f) {
  return new Getter((oe) => fail5(f(oe)));
}
function forbidden(message) {
  return fail6((oe) => new Forbidden(oe, {
    message: message(oe)
  }));
}
var passthrough_ = /* @__PURE__ */ new Getter(succeed5);
function isPassthrough(getter) {
  return getter.run === passthrough_.run;
}
function passthrough2() {
  return passthrough_;
}
function onSome(f) {
  return new Getter((oe, options) => isNone2(oe) ? succeedNone2 : f(oe.value, options));
}
function transform(f) {
  return transformOptional(map(f));
}
function transformOrFail(f) {
  return onSome((e, options) => f(e, options).pipe(mapEager2(some2)));
}
function transformOptional(f) {
  return new Getter((oe) => succeed5(f(oe)));
}
function withDefault(defaultValue) {
  return new Getter((o) => {
    const filtered = filter(o, isNotUndefined);
    return isSome2(filtered) ? succeed5(filtered) : map5(defaultValue, some2);
  });
}
function String2() {
  return transform(globalThis.String);
}
function Number3() {
  return transform(globalThis.Number);
}
function BigInt2() {
  return transform(globalThis.BigInt);
}
function Date2() {
  return transform((u) => new globalThis.Date(u));
}
function splitKeyValue(options) {
  const separator = options?.separator ?? ",";
  const keyValueSeparator = options?.keyValueSeparator ?? "=";
  return transform((input) => input.split(separator).reduce((acc, pair) => {
    const [key, value3] = pair.split(keyValueSeparator);
    if (key && value3) {
      acc[key] = value3;
    }
    return acc;
  }, {}));
}
function joinKeyValue(options) {
  const separator = options?.separator ?? ",";
  const keyValueSeparator = options?.keyValueSeparator ?? "=";
  return transform((input) => Object.entries(input).map(([key, value3]) => `${key}${keyValueSeparator}${value3}`).join(separator));
}
function split(options) {
  const separator = options?.separator ?? ",";
  return transform((input) => input === "" ? [] : input.split(separator));
}
function encodeBase642() {
  return transform(encodeBase64);
}
function decodeBase642() {
  return transformOrFail((input) => mapError(decodeBase64(input), (e) => new InvalidValue(some2(input), {
    message: e.message
  })).asEffect());
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/SchemaTransformation.js
class Middleware {
  _tag = "Middleware";
  decode;
  encode;
  constructor(decode, encode) {
    this.decode = decode;
    this.encode = encode;
  }
  flip() {
    return new Middleware(this.encode, this.decode);
  }
}
var TypeId13 = "~effect/SchemaTransformation/Transformation";

class Transformation {
  [TypeId13] = TypeId13;
  _tag = "Transformation";
  decode;
  encode;
  constructor(decode, encode) {
    this.decode = decode;
    this.encode = encode;
  }
  flip() {
    return new Transformation(this.encode, this.decode);
  }
  compose(other) {
    return new Transformation(this.decode.compose(other.decode), other.encode.compose(this.encode));
  }
}
function isTransformation(u) {
  return hasProperty(u, TypeId13);
}
var make8 = (options) => {
  if (isTransformation(options)) {
    return options;
  }
  return new Transformation(options.decode, options.encode);
};
function transformOrFail2(options) {
  return new Transformation(transformOrFail(options.decode), transformOrFail(options.encode));
}
function transform2(options) {
  return new Transformation(transform(options.decode), transform(options.encode));
}
function splitKeyValue2(options) {
  return new Transformation(splitKeyValue(options), joinKeyValue(options));
}
var passthrough_2 = /* @__PURE__ */ new Transformation(/* @__PURE__ */ passthrough2(), /* @__PURE__ */ passthrough2());
function passthrough3() {
  return passthrough_2;
}
var numberFromString = /* @__PURE__ */ new Transformation(/* @__PURE__ */ Number3(), /* @__PURE__ */ String2());
var bigintFromString = /* @__PURE__ */ new Transformation(/* @__PURE__ */ BigInt2(), /* @__PURE__ */ String2());
var dateFromString = /* @__PURE__ */ new Transformation(/* @__PURE__ */ Date2(), /* @__PURE__ */ transform(formatDate));
var errorFromErrorJsonEncoded = (options) => transform2({
  decode: (i) => {
    const err = new Error(i.message);
    if (typeof i.name === "string" && i.name !== "Error")
      err.name = i.name;
    if (typeof i.stack === "string")
      err.stack = i.stack;
    return err;
  },
  encode: (a) => {
    const e = {
      name: a.name,
      message: a.message
    };
    if (options?.includeStack && typeof a.stack === "string") {
      e.stack = a.stack;
    }
    return e;
  }
});
var urlFromString = /* @__PURE__ */ transformOrFail2({
  decode: (s) => try_2({
    try: () => new URL(s),
    catch: (e) => new InvalidValue(some2(s), {
      message: globalThis.String(e)
    })
  }),
  encode: (url) => succeed5(url.href)
});
var uint8ArrayFromBase64String = /* @__PURE__ */ new Transformation(/* @__PURE__ */ decodeBase642(), /* @__PURE__ */ encodeBase642());

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/SchemaAST.js
function makeGuard(tag) {
  return (ast) => ast._tag === tag;
}
var isDeclaration = /* @__PURE__ */ makeGuard("Declaration");
var isNever2 = /* @__PURE__ */ makeGuard("Never");
var isLiteral = /* @__PURE__ */ makeGuard("Literal");
var isUniqueSymbol = /* @__PURE__ */ makeGuard("UniqueSymbol");
var isArrays = /* @__PURE__ */ makeGuard("Arrays");
var isObjects = /* @__PURE__ */ makeGuard("Objects");
var isUnion = /* @__PURE__ */ makeGuard("Union");
class Link {
  to;
  transformation;
  constructor(to, transformation) {
    this.to = to;
    this.transformation = transformation;
  }
}
var defaultParseOptions = {};

class Context {
  isOptional;
  isMutable;
  defaultValue;
  annotations;
  constructor(isOptional, isMutable, defaultValue = undefined, annotations = undefined) {
    this.isOptional = isOptional;
    this.isMutable = isMutable;
    this.defaultValue = defaultValue;
    this.annotations = annotations;
  }
}
var TypeId14 = "~effect/Schema";

class Base2 {
  [TypeId14] = TypeId14;
  annotations;
  checks;
  encoding;
  context;
  constructor(annotations = undefined, checks = undefined, encoding = undefined, context3 = undefined) {
    this.annotations = annotations;
    this.checks = checks;
    this.encoding = encoding;
    this.context = context3;
  }
  toString() {
    return `<${this._tag}>`;
  }
}

class Declaration extends Base2 {
  _tag = "Declaration";
  typeParameters;
  run;
  constructor(typeParameters, run, annotations, checks, encoding, context3) {
    super(annotations, checks, encoding, context3);
    this.typeParameters = typeParameters;
    this.run = run;
  }
  getParser() {
    const run = this.run(this.typeParameters);
    return (oinput, options) => {
      if (isNone2(oinput))
        return succeedNone2;
      return mapEager2(run(oinput.value, this, options), some2);
    };
  }
  recur(recur) {
    const tps = mapOrSame(this.typeParameters, recur);
    return tps === this.typeParameters ? this : new Declaration(tps, this.run, this.annotations, this.checks, undefined, this.context);
  }
  getExpected() {
    const expected = this.annotations?.expected;
    if (typeof expected === "string")
      return expected;
    return "<Declaration>";
  }
}

class Null extends Base2 {
  _tag = "Null";
  getParser() {
    return fromConst(this, null);
  }
  getExpected() {
    return "null";
  }
}
var null_ = /* @__PURE__ */ new Null;
class Undefined extends Base2 {
  _tag = "Undefined";
  getParser() {
    return fromConst(this, undefined);
  }
  toCodecJson() {
    return replaceEncoding(this, [undefinedToNull]);
  }
  getExpected() {
    return "undefined";
  }
}
var undefinedToNull = /* @__PURE__ */ new Link(null_, /* @__PURE__ */ new Transformation(/* @__PURE__ */ transform(() => {
  return;
}), /* @__PURE__ */ transform(() => null)));
var undefined_3 = /* @__PURE__ */ new Undefined;
class Any extends Base2 {
  _tag = "Any";
  getParser() {
    return fromRefinement(this, isUnknown);
  }
  getExpected() {
    return "any";
  }
}
var any = /* @__PURE__ */ new Any;

class Unknown extends Base2 {
  _tag = "Unknown";
  getParser() {
    return fromRefinement(this, isUnknown);
  }
  getExpected() {
    return "unknown";
  }
}
var unknown = /* @__PURE__ */ new Unknown;
class Literal extends Base2 {
  _tag = "Literal";
  literal;
  constructor(literal, annotations, checks, encoding, context3) {
    super(annotations, checks, encoding, context3);
    if (typeof literal === "number" && !globalThis.Number.isFinite(literal)) {
      throw new Error(`A numeric literal must be finite, got ${format(literal)}`);
    }
    this.literal = literal;
  }
  getParser() {
    return fromConst(this, this.literal);
  }
  toCodecJson() {
    return typeof this.literal === "bigint" ? literalToString(this) : this;
  }
  toCodecStringTree() {
    return typeof this.literal === "string" ? this : literalToString(this);
  }
  getExpected() {
    return typeof this.literal === "string" ? JSON.stringify(this.literal) : globalThis.String(this.literal);
  }
}
function literalToString(ast) {
  const literalAsString = globalThis.String(ast.literal);
  return replaceEncoding(ast, [new Link(new Literal(literalAsString), new Transformation(transform(() => ast.literal), transform(() => literalAsString)))]);
}

class String3 extends Base2 {
  _tag = "String";
  getParser() {
    return fromRefinement(this, isString);
  }
  getExpected() {
    return "string";
  }
}
var string2 = /* @__PURE__ */ new String3;

class Number4 extends Base2 {
  _tag = "Number";
  getParser() {
    return fromRefinement(this, isNumber);
  }
  toCodecJson() {
    if (this.checks && (hasCheck(this.checks, "isFinite") || hasCheck(this.checks, "isInt"))) {
      return this;
    }
    return replaceEncoding(this, [numberToJson]);
  }
  toCodecStringTree() {
    if (this.checks && (hasCheck(this.checks, "isFinite") || hasCheck(this.checks, "isInt"))) {
      return replaceEncoding(this, [finiteToString]);
    }
    return replaceEncoding(this, [numberToString]);
  }
  getExpected() {
    return "number";
  }
}
function hasCheck(checks, tag) {
  return checks.some((c) => {
    switch (c._tag) {
      case "Filter":
        return c.annotations?.meta?._tag === tag;
      case "FilterGroup":
        return hasCheck(c.checks, tag);
    }
  });
}
var number2 = /* @__PURE__ */ new Number4;

class Boolean extends Base2 {
  _tag = "Boolean";
  getParser() {
    return fromRefinement(this, isBoolean);
  }
  getExpected() {
    return "boolean";
  }
}
var boolean = /* @__PURE__ */ new Boolean;
class BigInt3 extends Base2 {
  _tag = "BigInt";
  getParser() {
    return fromRefinement(this, isBigInt);
  }
  toCodecStringTree() {
    return replaceEncoding(this, [bigIntToString]);
  }
  getExpected() {
    return "bigint";
  }
}
var bigInt = /* @__PURE__ */ new BigInt3;

class Arrays extends Base2 {
  _tag = "Arrays";
  isMutable;
  elements;
  rest;
  constructor(isMutable, elements, rest, annotations, checks, encoding, context3) {
    super(annotations, checks, encoding, context3);
    this.isMutable = isMutable;
    this.elements = elements;
    this.rest = rest;
    const i = elements.findIndex(isOptional);
    if (i !== -1 && (elements.slice(i + 1).some((e) => !isOptional(e)) || rest.length > 1)) {
      throw new Error("A required element cannot follow an optional element. ts(1257)");
    }
    if (rest.length > 1 && rest.slice(1).some(isOptional)) {
      throw new Error("An optional element cannot follow a rest element. ts(1266)");
    }
  }
  getParser(recur) {
    const ast = this;
    const elements = ast.elements.map((ast2) => ({
      ast: ast2,
      parser: recur(ast2)
    }));
    const rest = ast.rest.map((ast2) => ({
      ast: ast2,
      parser: recur(ast2)
    }));
    const elementLen = elements.length;
    const [head, ...tail] = rest;
    const tailLen = tail.length;
    function getParser(tailThreshold, index) {
      if (index < elementLen) {
        return elements[index];
      } else if (index >= tailThreshold) {
        return tail[index - tailThreshold];
      }
      return head;
    }
    return fnUntracedEager2(function* (oinput, options) {
      if (oinput._tag === "None") {
        return oinput;
      }
      const input = oinput.value;
      if (!Array.isArray(input)) {
        return yield* fail5(new InvalidType(ast, oinput));
      }
      const len = input.length;
      const state = {
        ast,
        getParser,
        oinput,
        len,
        tailThreshold: resolveTailThreshold(len, elementLen, tailLen),
        output: new globalThis.Array(len),
        issues: undefined,
        options
      };
      const concurrency = resolveConcurrency(options?.concurrency);
      const eff = parseArray(state, input, {
        concurrency: concurrency?.concurrency,
        end: ast.rest.length === 0 ? elementLen : Math.max(len, elementLen + tailLen)
      });
      if (eff)
        yield* eff;
      if (ast.rest.length === 0 && len > elementLen) {
        for (let i = elementLen;i <= len - 1; i++) {
          const issue = new Pointer([i], new UnexpectedKey(ast, input[i]));
          if (options.errors === "all") {
            if (state.issues)
              state.issues.push(issue);
            else
              state.issues = [issue];
          } else {
            return yield* fail5(new Composite(ast, oinput, [issue]));
          }
        }
      }
      if (state.issues) {
        return yield* fail5(new Composite(ast, oinput, state.issues));
      }
      return some2(state.output);
    });
  }
  recur(recur) {
    const elements = mapOrSame(this.elements, recur);
    const rest = mapOrSame(this.rest, recur);
    return elements === this.elements && rest === this.rest ? this : new Arrays(this.isMutable, elements, rest, this.annotations, this.checks, undefined, this.context);
  }
  getExpected() {
    return "array";
  }
}
var parseArray = /* @__PURE__ */ iterateEager()({
  onItem(s, item, i) {
    const value3 = i < s.len ? some2(item) : none2();
    return s.getParser(s.tailThreshold, i).parser(value3, s.options);
  },
  step(s, _, exit3, i) {
    if (exit3._tag === "Failure") {
      return wrapPropertyKeyIssue(s, s.ast, i, exit3);
    } else if (exit3.value._tag === "Some") {
      s.output[i] = exit3.value.value;
    } else {
      const p = s.getParser(s.tailThreshold, i);
      if (isOptional(p.ast))
        return;
      const issue = new Pointer([i], new MissingKey(p.ast.context?.annotations));
      if (s.options.errors === "all") {
        if (s.issues)
          s.issues.push(issue);
        else
          s.issues = [issue];
      } else {
        return fail4(new Composite(s.ast, s.oinput, [issue]));
      }
    }
  }
});
function resolveTailThreshold(inputLen, elementLen, tailLen) {
  return Math.max(elementLen, inputLen - tailLen);
}
var resolveConcurrency = (value3) => {
  value3 = value3 === "unbounded" ? Infinity : value3 ?? 1;
  return value3 > 1 ? {
    concurrency: value3
  } : undefined;
};
var wrapPropertyKeyIssue = (s, ast, key, exit3) => {
  const issueResult = findError2(exit3.cause);
  if (isFailure2(issueResult)) {
    return exit3;
  }
  const issue = new Pointer([key], issueResult.success);
  if (s.options.errors === "all") {
    if (s.issues)
      s.issues.push(issue);
    else
      s.issues = [issue];
  } else {
    return fail4(new Composite(ast, s.oinput, [issue]));
  }
};
var FINITE_PATTERN = "[+-]?\\d*\\.?\\d+(?:[Ee][+-]?\\d+)?";
var isNumberStringRegExp = /* @__PURE__ */ new globalThis.RegExp(`(?:${FINITE_PATTERN}|Infinity|-Infinity|NaN)`);
function getIndexSignatureKeys(input, parameter) {
  const encoded = toEncoded(parameter);
  switch (encoded._tag) {
    case "String":
      return Object.keys(input);
    case "TemplateLiteral": {
      const regExp = getTemplateLiteralRegExp(encoded);
      return Object.keys(input).filter((k) => regExp.test(k));
    }
    case "Symbol":
      return Object.getOwnPropertySymbols(input);
    case "Number":
      return Object.keys(input).filter((k) => isNumberStringRegExp.test(k));
    case "Union":
      return [...new Set(encoded.types.flatMap((t) => getIndexSignatureKeys(input, t)))];
    default:
      return [];
  }
}

class PropertySignature {
  name;
  type;
  constructor(name, type) {
    this.name = name;
    this.type = type;
  }
}

class KeyValueCombiner {
  decode;
  encode;
  constructor(decode, encode) {
    this.decode = decode;
    this.encode = encode;
  }
  flip() {
    return new KeyValueCombiner(this.encode, this.decode);
  }
}

class IndexSignature {
  parameter;
  type;
  merge;
  constructor(parameter, type, merge3) {
    this.parameter = parameter;
    this.type = type;
    this.merge = merge3;
    if (isOptional(type) && !containsUndefined(type)) {
      throw new Error("Cannot use `Schema.optionalKey` with index signatures, use `Schema.optional` instead.");
    }
  }
}

class Objects extends Base2 {
  _tag = "Objects";
  propertySignatures;
  indexSignatures;
  constructor(propertySignatures, indexSignatures, annotations, checks, encoding, context3) {
    super(annotations, checks, encoding, context3);
    this.propertySignatures = propertySignatures;
    this.indexSignatures = indexSignatures;
    const duplicates = propertySignatures.map((ps) => ps.name).filter((name, i, arr) => arr.indexOf(name) !== i);
    if (duplicates.length > 0) {
      throw new Error(`Duplicate identifiers: ${JSON.stringify(duplicates)}. ts(2300)`);
    }
  }
  getParser(recur) {
    const ast = this;
    const expectedKeys = [];
    const expectedKeysSet = new Set;
    const properties = [];
    for (const ps of ast.propertySignatures) {
      expectedKeys.push(ps.name);
      expectedKeysSet.add(ps.name);
      properties.push({
        ps,
        parser: recur(ps.type),
        name: ps.name,
        type: ps.type
      });
    }
    const indexCount = ast.indexSignatures.length;
    if (ast.propertySignatures.length === 0 && ast.indexSignatures.length === 0) {
      return fromRefinement(ast, isNotNullish);
    }
    const parseIndexes = indexCount > 0 ? iterateEager()({
      onItem: fnUntracedEager2(function* (s, [key, is]) {
        const parserKey = recur(indexSignatureParameterFromString(is.parameter));
        const effKey = parserKey(some2(key), s.options);
        const exitKey = effectIsExit(effKey) ? effKey : yield* exit2(effKey);
        if (exitKey._tag === "Failure") {
          const eff = wrapPropertyKeyIssue(s, ast, key, exitKey);
          if (eff)
            yield* eff;
          return;
        }
        const value3 = some2(s.input[key]);
        const parserValue = recur(is.type);
        const effValue = parserValue(value3, s.options);
        const exitValue = effectIsExit(effValue) ? effValue : yield* exit2(effValue);
        if (exitValue._tag === "Failure") {
          const eff = wrapPropertyKeyIssue(s, ast, key, exitValue);
          if (eff)
            yield* eff;
          return;
        } else if (exitKey.value._tag === "Some" && exitValue.value._tag === "Some") {
          const k2 = exitKey.value.value;
          const v2 = exitValue.value.value;
          if (is.merge && is.merge.decode && Object.hasOwn(s.out, k2)) {
            const [k, v] = is.merge.decode.combine([k2, s.out[k2]], [k2, v2]);
            set(s.out, k, v);
          } else {
            set(s.out, k2, v2);
          }
        }
      }),
      step: (_s, _, exit3) => exit3._tag === "Failure" ? exit3 : undefined
    }) : undefined;
    return fnUntracedEager2(function* (oinput, options) {
      if (oinput._tag === "None") {
        return oinput;
      }
      const input = oinput.value;
      if (!(typeof input === "object" && input !== null && !Array.isArray(input))) {
        return yield* fail5(new InvalidType(ast, oinput));
      }
      const out = {};
      const state = {
        ast,
        oinput,
        input,
        out,
        issues: undefined,
        options
      };
      const errorsAllOption = options.errors === "all";
      const onExcessPropertyError = options.onExcessProperty === "error";
      const onExcessPropertyPreserve = options.onExcessProperty === "preserve";
      let inputKeys;
      if (ast.indexSignatures.length === 0 && (onExcessPropertyError || onExcessPropertyPreserve)) {
        inputKeys = Reflect.ownKeys(input);
        for (let i = 0;i < inputKeys.length; i++) {
          const key = inputKeys[i];
          if (!expectedKeysSet.has(key)) {
            if (onExcessPropertyError) {
              const issue = new Pointer([key], new UnexpectedKey(ast, input[key]));
              if (errorsAllOption) {
                if (state.issues) {
                  state.issues.push(issue);
                } else {
                  state.issues = [issue];
                }
                continue;
              } else {
                return yield* fail5(new Composite(ast, oinput, [issue]));
              }
            } else {
              set(out, key, input[key]);
            }
          }
        }
      }
      const concurrency = resolveConcurrency(options?.concurrency);
      const eff = parseProperties(state, properties, concurrency);
      if (eff)
        yield* eff;
      if (parseIndexes) {
        const keyPairs = empty();
        for (let i = 0;i < indexCount; i++) {
          const is = ast.indexSignatures[i];
          const keys2 = getIndexSignatureKeys(input, is.parameter);
          for (let j = 0;j < keys2.length; j++) {
            const key = keys2[j];
            keyPairs.push([key, is]);
          }
        }
        const eff2 = parseIndexes(state, keyPairs, concurrency);
        if (eff2)
          yield* eff2;
      }
      if (state.issues) {
        return yield* fail5(new Composite(ast, oinput, state.issues));
      }
      if (options.propertyOrder === "original") {
        const keys2 = (inputKeys ?? Reflect.ownKeys(input)).concat(expectedKeys);
        const preserved = {};
        for (const key of keys2) {
          if (Object.hasOwn(out, key)) {
            set(preserved, key, out[key]);
          }
        }
        return some2(preserved);
      }
      return some2(out);
    });
  }
  rebuild(recur, flipMerge) {
    const props = mapOrSame(this.propertySignatures, (ps) => {
      const t = recur(ps.type);
      return t === ps.type ? ps : new PropertySignature(ps.name, t);
    });
    const indexes = mapOrSame(this.indexSignatures, (is) => {
      const p = recur(is.parameter);
      const t = recur(is.type);
      const merge3 = flipMerge ? is.merge?.flip() : is.merge;
      return p === is.parameter && t === is.type && merge3 === is.merge ? is : new IndexSignature(p, t, merge3);
    });
    return props === this.propertySignatures && indexes === this.indexSignatures ? this : new Objects(props, indexes, this.annotations, this.checks, undefined, this.context);
  }
  flip(recur) {
    return this.rebuild(recur, true);
  }
  recur(recur) {
    return this.rebuild(recur, false);
  }
  getExpected() {
    if (this.propertySignatures.length === 0 && this.indexSignatures.length === 0)
      return "object | array";
    return "object";
  }
}
var parseProperties = /* @__PURE__ */ iterateEager()({
  onItem(s, p) {
    const value3 = Object.hasOwn(s.input, p.name) ? some2(s.input[p.name]) : none2();
    return p.parser(value3, s.options);
  },
  step(s, p, exit3) {
    if (exit3._tag === "Failure") {
      return wrapPropertyKeyIssue(s, s.ast, p.name, exit3);
    } else if (exit3.value._tag === "Some") {
      set(s.out, p.name, exit3.value.value);
    } else if (!isOptional(p.type)) {
      const issue = new Pointer([p.name], new MissingKey(p.type.context?.annotations));
      if (s.options.errors === "all") {
        if (s.issues)
          s.issues.push(issue);
        else
          s.issues = [issue];
        return;
      } else {
        return fail4(new Composite(s.ast, s.oinput, [issue]));
      }
    }
  }
});
function struct(fields, checks, annotations) {
  return new Objects(Reflect.ownKeys(fields).map((key) => {
    return new PropertySignature(key, fields[key].ast);
  }), [], annotations, checks);
}
function getAST(self) {
  return self.ast;
}
function tuple(elements, checks = undefined) {
  return new Arrays(false, elements.map((e) => e.ast), [], undefined, checks);
}
function union2(members, mode, checks) {
  return new Union(members.map(getAST), mode, undefined, checks);
}
function getCandidateTypes(ast) {
  switch (ast._tag) {
    case "Null":
      return ["null"];
    case "Undefined":
    case "Void":
      return ["undefined"];
    case "String":
    case "TemplateLiteral":
      return ["string"];
    case "Number":
      return ["number"];
    case "Boolean":
      return ["boolean"];
    case "Symbol":
    case "UniqueSymbol":
      return ["symbol"];
    case "BigInt":
      return ["bigint"];
    case "Arrays":
      return ["array"];
    case "ObjectKeyword":
      return ["object", "array", "function"];
    case "Objects":
      return ast.propertySignatures.length || ast.indexSignatures.length ? ["object"] : ["object", "array"];
    case "Enum":
      return Array.from(new Set(ast.enums.map(([, v]) => typeof v)));
    case "Literal":
      return [typeof ast.literal];
    case "Union":
      return Array.from(new Set(ast.types.flatMap(getCandidateTypes)));
    default:
      return ["null", "undefined", "string", "number", "boolean", "symbol", "bigint", "object", "array", "function"];
  }
}
function collectSentinels(ast) {
  switch (ast._tag) {
    default:
      return [];
    case "Declaration": {
      const s = ast.annotations?.["~sentinels"];
      return Array.isArray(s) ? s : [];
    }
    case "Objects":
      return ast.propertySignatures.flatMap((ps) => {
        const type = ps.type;
        if (!isOptional(type)) {
          if (isLiteral(type)) {
            return [{
              key: ps.name,
              literal: type.literal
            }];
          }
          if (isUniqueSymbol(type)) {
            return [{
              key: ps.name,
              literal: type.symbol
            }];
          }
        }
        return [];
      });
    case "Arrays":
      return ast.elements.flatMap((e, i) => {
        return isLiteral(e) && !isOptional(e) ? [{
          key: i,
          literal: e.literal
        }] : [];
      });
    case "Suspend":
      return collectSentinels(ast.thunk());
  }
}
var candidateIndexCache = /* @__PURE__ */ new WeakMap;
function getIndex(types) {
  let idx = candidateIndexCache.get(types);
  if (idx)
    return idx;
  idx = {};
  for (const a of types) {
    const encoded = toEncoded(a);
    if (isNever2(encoded))
      continue;
    const types2 = getCandidateTypes(encoded);
    const sentinels = collectSentinels(encoded);
    idx.byType ??= {};
    for (const t of types2)
      (idx.byType[t] ??= []).push(a);
    if (sentinels.length > 0) {
      idx.bySentinel ??= new Map;
      for (const {
        key,
        literal
      } of sentinels) {
        let m = idx.bySentinel.get(key);
        if (!m)
          idx.bySentinel.set(key, m = new Map);
        let arr = m.get(literal);
        if (!arr)
          m.set(literal, arr = []);
        arr.push(a);
      }
    } else {
      idx.otherwise ??= {};
      for (const t of types2)
        (idx.otherwise[t] ??= []).push(a);
    }
  }
  candidateIndexCache.set(types, idx);
  return idx;
}
function filterLiterals(input) {
  return (ast) => {
    const encoded = toEncoded(ast);
    return encoded._tag === "Literal" ? encoded.literal === input : encoded._tag === "UniqueSymbol" ? encoded.symbol === input : true;
  };
}
function getCandidates(input, types) {
  const idx = getIndex(types);
  const runtimeType = input === null ? "null" : Array.isArray(input) ? "array" : typeof input;
  if (idx.bySentinel) {
    const base = idx.otherwise?.[runtimeType] ?? [];
    if (runtimeType === "object" || runtimeType === "array") {
      for (const [k, m] of idx.bySentinel) {
        if (Object.hasOwn(input, k)) {
          const match6 = m.get(input[k]);
          if (match6)
            return [...match6, ...base].filter(filterLiterals(input));
        }
      }
    }
    return base;
  }
  return (idx.byType?.[runtimeType] ?? []).filter(filterLiterals(input));
}

class Union extends Base2 {
  _tag = "Union";
  types;
  mode;
  constructor(types, mode, annotations, checks, encoding, context3) {
    super(annotations, checks, encoding, context3);
    this.types = types;
    this.mode = mode;
  }
  getParser(recur) {
    const ast = this;
    return (oinput, options) => {
      if (oinput._tag === "None") {
        return succeed5(oinput);
      }
      const input = oinput.value;
      const candidates = getCandidates(input, ast.types);
      const state = {
        ast,
        recur,
        oinput,
        input,
        out: undefined,
        successes: [],
        issues: undefined,
        options
      };
      const concurrency = resolveConcurrency(options?.concurrency);
      const eff = parseUnion(state, candidates, concurrency);
      if (!eff) {
        return state.out ? succeed5(state.out) : fail5(new AnyOf(ast, input, state.issues ?? []));
      }
      return flatMap3(eff, (_) => {
        return state.out ? succeed5(state.out) : fail5(new AnyOf(ast, input, state.issues ?? []));
      });
    };
  }
  recur(recur) {
    const types = mapOrSame(this.types, recur);
    return types === this.types ? this : new Union(types, this.mode, this.annotations, this.checks, undefined, this.context);
  }
  getExpected(getExpected2) {
    const expected = this.annotations?.expected;
    if (typeof expected === "string")
      return expected;
    if (this.types.length === 0)
      return "never";
    const types = this.types.map((type) => {
      const encoded = toEncoded(type);
      switch (encoded._tag) {
        case "Arrays": {
          const literals = encoded.elements.filter(isLiteral);
          if (literals.length > 0) {
            return `${formatIsMutable(encoded.isMutable)}[ ${literals.map((e) => getExpected2(e) + formatIsOptional(e.context?.isOptional)).join(", ")}, ... ]`;
          }
          break;
        }
        case "Objects": {
          const literals = encoded.propertySignatures.filter((ps) => isLiteral(ps.type));
          if (literals.length > 0) {
            return `{ ${literals.map((ps) => `${formatIsMutable(ps.type.context?.isMutable)}${formatPropertyKey(ps.name)}${formatIsOptional(ps.type.context?.isOptional)}: ${getExpected2(ps.type)}`).join(", ")}, ... }`;
          }
          break;
        }
      }
      return getExpected2(encoded);
    });
    return Array.from(new Set(types)).join(" | ");
  }
}
var parseUnion = /* @__PURE__ */ iterateEager()({
  onItem(s, ast) {
    const parser = s.recur(ast);
    return parser(s.oinput, s.options);
  },
  step(s, candidate, exit3) {
    if (exit3._tag === "Failure") {
      const issueResult = findError2(exit3.cause);
      if (isFailure2(issueResult)) {
        return exit3;
      }
      if (s.issues)
        s.issues.push(issueResult.success);
      else
        s.issues = [issueResult.success];
    } else {
      if (s.out && s.ast.mode === "oneOf") {
        s.successes.push(candidate);
        return fail4(new OneOf(s.ast, s.input, s.successes));
      }
      s.out = exit3.value;
      s.successes.push(candidate);
      if (s.ast.mode === "anyOf") {
        return void_2;
      }
    }
  }
});
var nonFiniteLiterals = /* @__PURE__ */ new Union([/* @__PURE__ */ new Literal("Infinity"), /* @__PURE__ */ new Literal("-Infinity"), /* @__PURE__ */ new Literal("NaN")], "anyOf");
var numberToJson = /* @__PURE__ */ new Link(/* @__PURE__ */ new Union([number2, nonFiniteLiterals], "anyOf"), /* @__PURE__ */ new Transformation(/* @__PURE__ */ Number3(), /* @__PURE__ */ transform((n) => globalThis.Number.isFinite(n) ? n : globalThis.String(n))));
function formatIsMutable(isMutable) {
  return isMutable ? "" : "readonly ";
}
function formatIsOptional(isOptional) {
  return isOptional ? "?" : "";
}
class Filter2 extends Class {
  _tag = "Filter";
  run;
  annotations;
  aborted;
  constructor(run, annotations = undefined, aborted = false) {
    super();
    this.run = run;
    this.annotations = annotations;
    this.aborted = aborted;
  }
  annotate(annotations) {
    return new Filter2(this.run, {
      ...this.annotations,
      ...annotations
    }, this.aborted);
  }
  abort() {
    return new Filter2(this.run, this.annotations, true);
  }
  and(other, annotations) {
    return new FilterGroup([this, other], annotations);
  }
}

class FilterGroup extends Class {
  _tag = "FilterGroup";
  checks;
  annotations;
  constructor(checks, annotations = undefined) {
    super();
    this.checks = checks;
    this.annotations = annotations;
  }
  annotate(annotations) {
    return new FilterGroup(this.checks, {
      ...this.annotations,
      ...annotations
    });
  }
  and(other, annotations) {
    return new FilterGroup([this, other], annotations);
  }
}
function makeFilter(filter6, annotations, aborted = false) {
  return new Filter2((input, ast, options) => make7(input, ast, filter6(input, ast, options)), annotations, aborted);
}
function isPattern(regExp, annotations) {
  const source = regExp.source;
  return makeFilter((s) => regExp.test(s), {
    expected: `a string matching the RegExp ${source}`,
    meta: {
      _tag: "isPattern",
      regExp
    },
    toArbitraryConstraint: {
      string: {
        patterns: [regExp.source]
      }
    },
    ...annotations
  });
}
function modifyOwnPropertyDescriptors(ast, f) {
  const d = Object.getOwnPropertyDescriptors(ast);
  f(d);
  return Object.create(Object.getPrototypeOf(ast), d);
}
function replaceEncoding(ast, encoding) {
  if (ast.encoding === encoding) {
    return ast;
  }
  return modifyOwnPropertyDescriptors(ast, (d) => {
    d.encoding.value = encoding;
  });
}
function replaceContext(ast, context3) {
  if (ast.context === context3) {
    return ast;
  }
  return modifyOwnPropertyDescriptors(ast, (d) => {
    d.context.value = context3;
  });
}
function annotate(ast, annotations) {
  if (ast.checks) {
    const last = ast.checks[ast.checks.length - 1];
    return replaceChecks(ast, append(ast.checks.slice(0, -1), last.annotate(annotations)));
  }
  return modifyOwnPropertyDescriptors(ast, (d) => {
    d.annotations.value = {
      ...d.annotations.value,
      ...annotations
    };
  });
}
function replaceChecks(ast, checks) {
  if (ast.checks === checks) {
    return ast;
  }
  return modifyOwnPropertyDescriptors(ast, (d) => {
    d.checks.value = checks;
  });
}
function appendChecks(ast, checks) {
  return replaceChecks(ast, ast.checks ? [...ast.checks, ...checks] : checks);
}
function updateLastLink(encoding, f) {
  const links = encoding;
  const last = links[links.length - 1];
  const to = f(last.to);
  if (to !== last.to) {
    return append(encoding.slice(0, encoding.length - 1), new Link(to, last.transformation));
  }
  return encoding;
}
function applyToLastLink(f) {
  return (ast) => ast.encoding ? replaceEncoding(ast, updateLastLink(ast.encoding, f)) : ast;
}
function middlewareDecoding(ast, middleware) {
  return appendTransformation(ast, middleware, toType(ast));
}
function appendTransformation(from, transformation, to) {
  const link = new Link(from, transformation);
  return replaceEncoding(to, to.encoding ? [...to.encoding, link] : [link]);
}
function mapOrSame(as3, f) {
  let changed = false;
  const out = new Array(as3.length);
  for (let i = 0;i < as3.length; i++) {
    const a = as3[i];
    const fa = f(a);
    if (fa !== a) {
      changed = true;
    }
    out[i] = fa;
  }
  return changed ? out : as3;
}
function annotateKey(ast, annotations) {
  const context3 = ast.context ? new Context(ast.context.isOptional, ast.context.isMutable, ast.context.defaultValue, {
    ...ast.context.annotations,
    ...annotations
  }) : new Context(false, false, undefined, annotations);
  return replaceContext(ast, context3);
}
var optionalKeyLastLink = /* @__PURE__ */ applyToLastLink(optionalKey);
function optionalKey(ast) {
  const context3 = ast.context ? ast.context.isOptional === false ? new Context(true, ast.context.isMutable, ast.context.defaultValue, ast.context.annotations) : ast.context : new Context(true, false);
  return optionalKeyLastLink(replaceContext(ast, context3));
}
function withConstructorDefault(ast, defaultValue) {
  const transformation = new Transformation(withDefault(defaultValue), passthrough2());
  const encoding = [new Link(unknown, transformation)];
  const context3 = ast.context ? new Context(ast.context.isOptional, ast.context.isMutable, encoding, ast.context.annotations) : new Context(false, false, encoding);
  return replaceContext(ast, context3);
}
function decodeTo(from, to, transformation) {
  return appendTransformation(from, transformation, to);
}
function parseParameter(ast) {
  switch (ast._tag) {
    case "Literal":
      return {
        literals: isPropertyKey(ast.literal) ? [ast.literal] : [],
        parameters: []
      };
    case "UniqueSymbol":
      return {
        literals: [ast.symbol],
        parameters: []
      };
    case "String":
    case "Number":
    case "Symbol":
    case "TemplateLiteral":
      return {
        literals: [],
        parameters: [ast]
      };
    case "Union": {
      const out = {
        literals: [],
        parameters: []
      };
      for (let i = 0;i < ast.types.length; i++) {
        const parsed = parseParameter(ast.types[i]);
        out.literals = out.literals.concat(parsed.literals);
        out.parameters = out.parameters.concat(parsed.parameters);
      }
      return out;
    }
  }
  return {
    literals: [],
    parameters: []
  };
}
function record(key, value3, keyValueCombiner) {
  const {
    literals,
    parameters: indexSignatures
  } = parseParameter(key);
  return new Objects(literals.map((literal) => new PropertySignature(literal, value3)), indexSignatures.map((parameter) => new IndexSignature(parameter, value3, keyValueCombiner)));
}
function isOptional(ast) {
  return ast.context?.isOptional ?? false;
}
var toType = /* @__PURE__ */ memoize((ast) => {
  if (ast.encoding) {
    return toType(replaceEncoding(ast, undefined));
  }
  const out = ast;
  return out.recur?.(toType) ?? out;
});
var toEncoded = /* @__PURE__ */ memoize((ast) => {
  return toType(flip3(ast));
});
function flipEncoding(ast, encoding) {
  const links = encoding;
  const len = links.length;
  const last = links[len - 1];
  const ls = [new Link(flip3(replaceEncoding(ast, undefined)), links[0].transformation.flip())];
  for (let i = 1;i < len; i++) {
    ls.unshift(new Link(flip3(links[i - 1].to), links[i].transformation.flip()));
  }
  const to = flip3(last.to);
  if (to.encoding) {
    return replaceEncoding(to, [...to.encoding, ...ls]);
  } else {
    return replaceEncoding(to, ls);
  }
}
var flip3 = /* @__PURE__ */ memoize((ast) => {
  if (ast.encoding) {
    return flipEncoding(ast, ast.encoding);
  }
  const out = ast;
  return out.flip?.(flip3) ?? out.recur?.(flip3) ?? out;
});
function containsUndefined(ast) {
  switch (ast._tag) {
    case "Undefined":
      return true;
    case "Union":
      return ast.types.some(containsUndefined);
    default:
      return false;
  }
}
function getTemplateLiteralSource(ast, top) {
  return ast.encodedParts.map((part) => handleTemplateLiteralASTPartParens(part, getTemplateLiteralASTPartPattern(part), top)).join("");
}
var getTemplateLiteralRegExp = /* @__PURE__ */ memoize((ast) => {
  return new globalThis.RegExp(`^${getTemplateLiteralSource(ast, true)}$`);
});
function getTemplateLiteralASTPartPattern(part) {
  switch (part._tag) {
    case "Literal":
      return escape(globalThis.String(part.literal));
    case "String":
      return STRING_PATTERN;
    case "Number":
      return FINITE_PATTERN;
    case "BigInt":
      return BIGINT_PATTERN;
    case "TemplateLiteral":
      return getTemplateLiteralSource(part, false);
    case "Union":
      return part.types.map(getTemplateLiteralASTPartPattern).join("|");
  }
}
function handleTemplateLiteralASTPartParens(part, s, top) {
  if (isUnion(part)) {
    if (!top) {
      return `(?:${s})`;
    }
  } else if (!top) {
    return s;
  }
  return `(${s})`;
}
function fromConst(ast, value3) {
  const succeed6 = succeedSome2(value3);
  return (oinput) => {
    if (oinput._tag === "None") {
      return succeedNone2;
    }
    return oinput.value === value3 ? succeed6 : fail5(new InvalidType(ast, oinput));
  };
}
function fromRefinement(ast, refinement) {
  return (oinput) => {
    if (oinput._tag === "None") {
      return succeedNone2;
    }
    return refinement(oinput.value) ? succeed5(oinput) : fail5(new InvalidType(ast, oinput));
  };
}
function toCodec(f) {
  function out(ast) {
    return ast.encoding ? replaceEncoding(ast, updateLastLink(ast.encoding, out)) : f(ast);
  }
  return memoize(out);
}
var indexSignatureParameterFromString = /* @__PURE__ */ toCodec((ast) => {
  switch (ast._tag) {
    default:
      return ast;
    case "Number":
      return ast.toCodecStringTree();
    case "Union":
      return ast.recur(indexSignatureParameterFromString);
  }
});
var STRING_PATTERN = "[\\s\\S]*?";
var isStringFiniteRegExp = /* @__PURE__ */ new globalThis.RegExp(`^${FINITE_PATTERN}$`);
function isStringFinite(annotations) {
  return isPattern(isStringFiniteRegExp, {
    expected: "a string representing a finite number",
    meta: {
      _tag: "isStringFinite",
      regExp: isStringFiniteRegExp
    },
    ...annotations
  });
}
var finiteString = /* @__PURE__ */ appendChecks(string2, [/* @__PURE__ */ isStringFinite()]);
var finiteToString = /* @__PURE__ */ new Link(finiteString, numberFromString);
var numberToString = /* @__PURE__ */ new Link(/* @__PURE__ */ new Union([finiteString, nonFiniteLiterals], "anyOf"), numberFromString);
var BIGINT_PATTERN = "-?\\d+";
var isStringBigIntRegExp = /* @__PURE__ */ new globalThis.RegExp(`^${BIGINT_PATTERN}$`);
function isStringBigInt(annotations) {
  return isPattern(isStringBigIntRegExp, {
    expected: "a string representing a bigint",
    meta: {
      _tag: "isStringBigInt",
      regExp: isStringBigIntRegExp
    },
    ...annotations
  });
}
var bigIntString = /* @__PURE__ */ appendChecks(string2, [/* @__PURE__ */ isStringBigInt({
  expected: "a string representing a bigint"
})]);
var bigIntToString = /* @__PURE__ */ new Link(bigIntString, bigintFromString);
var REGEXP_PATTERN = "Symbol\\((.*)\\)";
var isStringSymbolRegExp = /* @__PURE__ */ new globalThis.RegExp(`^${REGEXP_PATTERN}$`);
function collectIssues(checks, value3, issues, ast, options) {
  for (let i = 0;i < checks.length; i++) {
    const check = checks[i];
    if (check._tag === "FilterGroup") {
      collectIssues(check.checks, value3, issues, ast, options);
    } else {
      const issue = check.run(value3, ast, options);
      if (issue) {
        issues.push(new Filter(value3, check, issue));
        if (check.aborted || options?.errors !== "all") {
          return;
        }
      }
    }
  }
}
var ClassTypeId = "~effect/Schema/Class";
var STRUCTURAL_ANNOTATION_KEY = "~structural";
function isStringTree(u) {
  const seen = new Set;
  return recur(u);
  function recur(u2) {
    if (u2 === undefined || typeof u2 === "string") {
      return true;
    }
    if (typeof u2 !== "object" || u2 === null) {
      return false;
    }
    if (seen.has(u2)) {
      return false;
    }
    seen.add(u2);
    if (Array.isArray(u2)) {
      return u2.every(recur);
    }
    return Object.keys(u2).every((key) => recur(u2[key]));
  }
}
var StringTree = /* @__PURE__ */ new Declaration([], () => (input, ast) => isStringTree(input) ? succeed5(input) : fail5(new InvalidType(ast, some2(input))), {
  expected: "StringTree",
  toCodecStringTree: () => new Link(unknown, passthrough3())
});
var unknownToStringTree = /* @__PURE__ */ new Link(StringTree, /* @__PURE__ */ passthrough3());

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Struct.js
var lambda = (f) => f;

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/SchemaParser.js
var recurDefaults = /* @__PURE__ */ memoize((ast) => {
  switch (ast._tag) {
    case "Declaration": {
      const getLink = ast.annotations?.[ClassTypeId];
      if (isFunction(getLink)) {
        const link = getLink(ast.typeParameters);
        const to = recurDefaults(link.to);
        return replaceEncoding(ast, to === link.to ? [link] : [new Link(to, link.transformation)]);
      }
      return ast;
    }
    case "Objects":
    case "Arrays":
      return ast.recur((ast2) => {
        const defaultValue = ast2.context?.defaultValue;
        if (defaultValue) {
          return replaceEncoding(recurDefaults(ast2), defaultValue);
        }
        return recurDefaults(ast2);
      });
    case "Suspend":
      return ast.recur(recurDefaults);
    default:
      return ast;
  }
});
function makeEffect(schema) {
  const ast = recurDefaults(toType(schema.ast));
  const parser = run(ast);
  return (input, options) => {
    return parser(input, options?.disableChecks ? options?.parseOptions ? {
      ...options.parseOptions,
      disableChecks: true
    } : {
      disableChecks: true
    } : options?.parseOptions);
  };
}
function makeOption(schema) {
  const parser = makeEffect(schema);
  return (input, options) => {
    return getSuccess2(runSyncExit2(parser(input, options)));
  };
}
function makeUnsafe4(schema) {
  const parser = makeEffect(schema);
  return (input, options) => {
    return runSync2(mapErrorEager2(parser(input, options), (issue) => new Error(issue.toString(), {
      cause: issue
    })));
  };
}
function _is(ast) {
  const parser = asExit(run(toType(ast)));
  return (input) => {
    return isSuccess4(parser(input, defaultParseOptions));
  };
}
function decodeUnknownEffect(schema) {
  return run(schema.ast);
}
function run(ast) {
  const parser = recur(ast);
  return (input, options) => flatMapEager2(parser(some2(input), options ?? defaultParseOptions), (oa) => {
    if (oa._tag === "None") {
      return fail5(new InvalidValue(oa));
    }
    return succeed5(oa.value);
  });
}
function asExit(parser) {
  return (input, options) => runSyncExit2(parser(input, options));
}
var recur = /* @__PURE__ */ memoize((ast) => {
  let parser;
  const astOptions = resolve(ast)?.["parseOptions"];
  if (!ast.context && !ast.encoding && !ast.checks) {
    return (ou, options) => {
      parser ??= ast.getParser(recur);
      if (astOptions) {
        options = {
          ...options,
          ...astOptions
        };
      }
      return parser(ou, options);
    };
  }
  const isStructural = isArrays(ast) || isObjects(ast) || isDeclaration(ast) && ast.typeParameters.length > 0;
  return (ou, options) => {
    if (astOptions) {
      options = {
        ...options,
        ...astOptions
      };
    }
    const encoding = ast.encoding;
    let srou;
    if (encoding) {
      const links = encoding;
      const len = links.length;
      for (let i = len - 1;i >= 0; i--) {
        const link = links[i];
        const to = link.to;
        const parser2 = recur(to);
        srou = srou ? flatMapEager2(srou, (ou2) => parser2(ou2, options)) : parser2(ou, options);
        if (link.transformation._tag === "Transformation") {
          const getter = link.transformation.decode;
          srou = flatMapEager2(srou, (ou2) => getter.run(ou2, options));
        } else {
          srou = link.transformation.decode(srou, options);
        }
      }
      srou = mapErrorEager2(srou, (issue) => new Encoding(ast, ou, issue));
    }
    parser ??= ast.getParser(recur);
    let sroa = srou ? flatMapEager2(srou, (ou2) => parser(ou2, options)) : parser(ou, options);
    if (ast.checks && !options?.disableChecks) {
      const checks = ast.checks;
      if (options?.errors === "all" && isStructural && isSome2(ou)) {
        sroa = catchEager2(sroa, (issue) => {
          const issues = [];
          collectIssues(checks.filter((check) => check.annotations?.[STRUCTURAL_ANNOTATION_KEY]), ou.value, issues, ast, options);
          const out = isArrayNonEmpty2(issues) ? issue._tag === "Composite" && issue.ast === ast ? new Composite(ast, issue.actual, [...issue.issues, ...issues]) : new Composite(ast, ou, [issue, ...issues]) : issue;
          return fail5(out);
        });
      }
      sroa = flatMapEager2(sroa, (oa) => {
        if (isSome2(oa)) {
          const value3 = oa.value;
          const issues = [];
          collectIssues(checks, value3, issues, ast, options);
          if (isArrayNonEmpty2(issues)) {
            return fail5(new Composite(ast, oa, issues));
          }
        }
        return succeed5(oa);
      });
    }
    return sroa;
  };
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/internal/schema/schema.js
var TypeId15 = "~effect/Schema/Schema";
var SchemaProto = {
  [TypeId15]: TypeId15,
  pipe() {
    return pipeArguments(this, arguments);
  },
  annotate(annotations) {
    return this.rebuild(annotate(this.ast, annotations));
  },
  annotateKey(annotations) {
    return this.rebuild(annotateKey(this.ast, annotations));
  },
  check(...checks) {
    return this.rebuild(appendChecks(this.ast, checks));
  }
};
function make9(ast, options) {
  const self = Object.create(SchemaProto);
  if (options) {
    Object.assign(self, options);
  }
  self.ast = ast;
  self.rebuild = (ast2) => make9(ast2, options);
  self.makeEffect = flow(makeEffect(self), mapErrorEager2((issue) => new SchemaError(issue)));
  self.make = makeUnsafe4(self);
  self.makeOption = makeOption(self);
  return self;
}
var SchemaErrorTypeId = "~effect/Schema/SchemaError";

class SchemaError {
  [SchemaErrorTypeId] = SchemaErrorTypeId;
  _tag = "SchemaError";
  name = "SchemaError";
  issue;
  constructor(issue) {
    this.issue = issue;
  }
  get message() {
    return this.issue.toString();
  }
  toString() {
    return `SchemaError(${this.message})`;
  }
}
function makeReorder(getPriority) {
  return (types) => {
    const indexMap = new Map;
    for (let i = 0;i < types.length; i++) {
      indexMap.set(toEncoded(types[i]), i);
    }
    const sortedTypes = [...types].sort((a, b) => {
      a = toEncoded(a);
      b = toEncoded(b);
      const pa = getPriority(a);
      const pb = getPriority(b);
      if (pa !== pb)
        return pa - pb;
      return indexMap.get(a) - indexMap.get(b);
    });
    const orderChanged = sortedTypes.some((ast, index) => ast !== types[index]);
    if (!orderChanged)
      return types;
    return sortedTypes;
  };
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Schema.js
var TypeId16 = TypeId15;
function declareConstructor() {
  return (typeParameters, run2, annotations) => {
    return make10(new Declaration(typeParameters.map(getAST), (typeParameters2) => run2(typeParameters2.map((ast) => make10(ast))), annotations));
  };
}
function declare(is2, annotations) {
  return declareConstructor()([], () => (input, ast) => is2(input) ? succeed5(input) : fail5(new InvalidType(ast, some2(input))), annotations);
}
function isSchemaError(u) {
  return hasProperty(u, SchemaErrorTypeId);
}
var make10 = make9;
function isSchema(u) {
  return hasProperty(u, TypeId16) && u[TypeId16] === TypeId16;
}
var optionalKey2 = /* @__PURE__ */ lambda((schema) => make10(optionalKey(schema.ast), {
  schema
}));
function Literal2(literal) {
  const out = make10(new Literal(literal), {
    literal,
    transform(to) {
      return out.pipe(decodeTo2(Literal2(to), {
        decode: transform(() => to),
        encode: transform(() => literal)
      }));
    }
  });
  return out;
}
var Any2 = /* @__PURE__ */ make10(any);
var Unknown2 = /* @__PURE__ */ make10(unknown);
var String4 = /* @__PURE__ */ make10(string2);
var Number5 = /* @__PURE__ */ make10(number2);
var Boolean2 = /* @__PURE__ */ make10(boolean);
var BigInt5 = /* @__PURE__ */ make10(bigInt);
function makeStruct(ast, fields) {
  return make10(ast, {
    fields,
    mapFields(f, options) {
      const fields2 = f(this.fields);
      return makeStruct(struct(fields2, options?.unsafePreserveChecks ? this.ast.checks : undefined), fields2);
    }
  });
}
function Struct(fields) {
  return makeStruct(struct(fields, undefined), fields);
}
function Record(key, value3, options) {
  const keyValueCombiner = options?.keyValueCombiner?.decode || options?.keyValueCombiner?.encode ? new KeyValueCombiner(options.keyValueCombiner.decode, options.keyValueCombiner.encode) : undefined;
  return make10(record(key.ast, value3.ast, keyValueCombiner), {
    key,
    value: value3
  });
}
function makeTuple(ast, elements) {
  return make10(ast, {
    elements,
    mapElements(f, options) {
      const elements2 = f(this.elements);
      return makeTuple(tuple(elements2, options?.unsafePreserveChecks ? this.ast.checks : undefined), elements2);
    }
  });
}
function Tuple(elements) {
  return makeTuple(tuple(elements), elements);
}
var ArraySchema = /* @__PURE__ */ lambda((schema) => make10(new Arrays(false, [], [schema.ast]), {
  schema
}));
function makeUnion(ast, members) {
  return make10(ast, {
    members,
    mapMembers(f, options) {
      const members2 = f(this.members);
      return makeUnion(union2(members2, this.ast.mode, options?.unsafePreserveChecks ? this.ast.checks : undefined), members2);
    }
  });
}
function Union2(members, options) {
  return makeUnion(union2(members, options?.mode ?? "anyOf", undefined), members);
}
function Literals(literals) {
  const members = literals.map(Literal2);
  return make10(union2(members, "anyOf", undefined), {
    literals,
    members,
    mapMembers(f) {
      return Union2(f(this.members));
    },
    pick(literals2) {
      return Literals(literals2);
    },
    transform(to) {
      return Union2(members.map((member, index) => member.transform(to[index])));
    }
  });
}
function middlewareDecoding2(decode) {
  return (schema) => make10(middlewareDecoding(schema.ast, new Middleware(decode, identity)), {
    schema
  });
}
function decodeTo2(to, transformation) {
  return (from) => {
    return make10(decodeTo(from.ast, to.ast, transformation ? make8(transformation) : passthrough3()), {
      from,
      to
    });
  };
}
function withConstructorDefault2(defaultValue) {
  return (schema) => make10(withConstructorDefault(schema.ast, defaultValue), {
    schema
  });
}
function tag(literal) {
  return Literal2(literal).pipe(withConstructorDefault2(succeed5(literal)));
}
function TaggedStruct(value3, fields) {
  return Struct({
    _tag: tag(value3),
    ...fields
  });
}
function instanceOf(constructor, annotations) {
  return declare((u) => u instanceof constructor, annotations);
}
function link() {
  return (encodeTo, transformation) => {
    return new Link(encodeTo.ast, make8(transformation));
  };
}
var makeFilter2 = makeFilter;
var isPattern2 = isPattern;
function isBase64(annotations) {
  const regExp = /^([0-9a-zA-Z+/]{4})*(([0-9a-zA-Z+/]{2}==)|([0-9a-zA-Z+/]{3}=))?$/;
  return isPattern2(regExp, {
    expected: "a base64 encoded string",
    meta: {
      _tag: "isBase64",
      regExp
    },
    ...annotations
  });
}
function isFinite(annotations) {
  return makeFilter2((n) => globalThis.Number.isFinite(n), {
    expected: "a finite number",
    meta: {
      _tag: "isFinite"
    },
    toArbitraryConstraint: {
      number: {
        noDefaultInfinity: true,
        noNaN: true
      }
    },
    ...annotations
  });
}
function makeIsBetween(deriveOptions) {
  const greaterThanOrEqualTo = isGreaterThanOrEqualTo(deriveOptions.order);
  const greaterThan = isGreaterThan(deriveOptions.order);
  const lessThanOrEqualTo = isLessThanOrEqualTo(deriveOptions.order);
  const lessThan = isLessThan(deriveOptions.order);
  const formatter = deriveOptions.formatter ?? format;
  return (options, annotations) => {
    const gte = options.exclusiveMinimum ? greaterThan : greaterThanOrEqualTo;
    const lte = options.exclusiveMaximum ? lessThan : lessThanOrEqualTo;
    return makeFilter2((input) => gte(input, options.minimum) && lte(input, options.maximum), {
      expected: `a value between ${formatter(options.minimum)}${options.exclusiveMinimum ? " (excluded)" : ""} and ${formatter(options.maximum)}${options.exclusiveMaximum ? " (excluded)" : ""}`,
      ...deriveOptions.annotate?.(options),
      ...annotations
    });
  };
}
var isBetween = /* @__PURE__ */ makeIsBetween({
  order: Number2,
  annotate: (options) => {
    return {
      meta: {
        _tag: "isBetween",
        ...options
      },
      toArbitraryConstraint: {
        number: {
          min: options.minimum,
          max: options.maximum,
          ...options.exclusiveMinimum && {
            minExcluded: true
          },
          ...options.exclusiveMaximum && {
            maxExcluded: true
          }
        }
      }
    };
  }
});
function isInt(annotations) {
  return makeFilter2((n) => globalThis.Number.isSafeInteger(n), {
    expected: "an integer",
    meta: {
      _tag: "isInt"
    },
    toArbitraryConstraint: {
      number: {
        isInteger: true
      }
    },
    ...annotations
  });
}
function isDateValid(annotations) {
  return makeFilter2((date) => !isNaN(date.getTime()), {
    expected: "a valid date",
    meta: {
      _tag: "isDateValid"
    },
    toArbitraryConstraint: {
      date: {
        noInvalidDate: true
      }
    },
    ...annotations
  });
}
function isMinLength(minLength, annotations) {
  minLength = Math.max(0, Math.floor(minLength));
  return makeFilter2((input) => input.length >= minLength, {
    expected: `a value with a length of at least ${minLength}`,
    meta: {
      _tag: "isMinLength",
      minLength
    },
    [STRUCTURAL_ANNOTATION_KEY]: true,
    toArbitraryConstraint: {
      string: {
        minLength
      },
      array: {
        minLength
      }
    },
    ...annotations
  });
}
function isNonEmpty(annotations) {
  return isMinLength(1, annotations);
}
var NonEmptyString = /* @__PURE__ */ String4.check(/* @__PURE__ */ isNonEmpty());
function Redacted(value3, options) {
  const decodeLabel = typeof options?.label === "string" ? decodeUnknownEffect(Literal2(options.label)) : undefined;
  const schema = declareConstructor()([value3], ([value4]) => (input, ast, poptions) => {
    if (isRedacted(input)) {
      const label = decodeLabel !== undefined ? mapErrorEager2(decodeLabel(input.label, poptions), (issue) => new Pointer(["label"], issue)) : void_3;
      return flatMapEager2(label, () => mapBothEager2(decodeUnknownEffect(value4)(value2(input), poptions), {
        onSuccess: () => input,
        onFailure: () => {
          const oinput = some2(input);
          return new Composite(ast, oinput, [new Pointer(["value"], new InvalidValue(oinput))]);
        }
      }));
    }
    return fail5(new InvalidType(ast, some2(input)));
  }, {
    typeConstructor: {
      _tag: "effect/Redacted"
    },
    generation: {
      runtime: `Schema.Redacted(?)`,
      Type: `Redacted.Redacted<?>`,
      importDeclaration: `import * as Redacted from "effect/Redacted"`
    },
    expected: "Redacted",
    toCodecJson: ([value4]) => link()(redact3(value4), {
      decode: transform((e) => make6(e, {
        label: options?.label
      })),
      encode: forbidden((oe) => "Cannot serialize Redacted" + (isSome2(oe) && typeof oe.value.label === "string" ? ` with label: "${oe.value.label}"` : ""))
    }),
    toArbitrary: ([value4]) => () => value4.map((a) => make6(a, {
      label: options?.label
    })),
    toFormatter: () => globalThis.String,
    toEquivalence: ([value4]) => makeEquivalence(value4)
  });
  return make10(schema.ast, {
    value: value3
  });
}
function redact3(schema) {
  return schema.pipe(middlewareDecoding2(mapErrorEager2(redact2)));
}
var ErrorJsonEncoded = /* @__PURE__ */ Struct({
  message: String4,
  name: /* @__PURE__ */ optionalKey2(String4),
  stack: /* @__PURE__ */ optionalKey2(String4)
});
var Error3 = /* @__PURE__ */ instanceOf(globalThis.Error, {
  typeConstructor: {
    _tag: "Error"
  },
  generation: {
    runtime: `Schema.Error`,
    Type: `globalThis.Error`
  },
  expected: "Error",
  toCodecJson: () => link()(ErrorJsonEncoded, errorFromErrorJsonEncoded()),
  toArbitrary: () => (fc) => fc.string().map((message) => new globalThis.Error(message))
});
var ErrorWithStack = /* @__PURE__ */ instanceOf(globalThis.Error, {
  typeConstructor: {
    _tag: "ErrorWithStack"
  },
  generation: {
    runtime: `Schema.ErrorWithStack`,
    Type: `globalThis.Error`
  },
  expected: "Error",
  toCodecJson: () => link()(ErrorJsonEncoded, errorFromErrorJsonEncoded({
    includeStack: true
  })),
  toArbitrary: () => (fc) => fc.string().map((message) => new globalThis.Error(message))
});
var defectTransformation = /* @__PURE__ */ new Transformation(/* @__PURE__ */ passthrough2(), /* @__PURE__ */ transform((u) => {
  try {
    return JSON.parse(JSON.stringify(u));
  } catch {
    return format(u);
  }
}));
var Defect = /* @__PURE__ */ Union2([/* @__PURE__ */ ErrorJsonEncoded.pipe(/* @__PURE__ */ decodeTo2(Error3, /* @__PURE__ */ errorFromErrorJsonEncoded())), /* @__PURE__ */ Any2.pipe(/* @__PURE__ */ decodeTo2(/* @__PURE__ */ Unknown2.annotate({
  toCodecJson: () => link()(Any2, defectTransformation),
  toArbitrary: () => (fc) => fc.json()
}), defectTransformation))]);
var RegExp3 = /* @__PURE__ */ instanceOf(globalThis.RegExp, {
  typeConstructor: {
    _tag: "RegExp"
  },
  generation: {
    runtime: `Schema.RegExp`,
    Type: `globalThis.RegExp`
  },
  expected: "RegExp",
  toCodecJson: () => link()(Struct({
    source: String4,
    flags: String4
  }), transformOrFail2({
    decode: (e) => try_2({
      try: () => new globalThis.RegExp(e.source, e.flags),
      catch: (e2) => new InvalidValue(some2(e2), {
        message: globalThis.String(e2)
      })
    }),
    encode: (regExp) => succeed5({
      source: regExp.source,
      flags: regExp.flags
    })
  })),
  toArbitrary: () => (fc) => fc.tuple(fc.constantFrom(".", ".*", "\\d+", "\\w+", "[a-z]+", "[A-Z]+", "[0-9]+", "^[a-zA-Z0-9]+$", "^\\d{4}-\\d{2}-\\d{2}$"), fc.uniqueArray(fc.constantFrom("g", "i", "m", "s", "u", "y"), {
    minLength: 0,
    maxLength: 6
  }).map((flags) => flags.join(""))).map(([source, flags]) => new globalThis.RegExp(source, flags)),
  toEquivalence: () => (a, b) => a.source === b.source && a.flags === b.flags
});
var URLString = /* @__PURE__ */ String4.annotate({
  expected: "a string that will be decoded as a URL"
});
var URL2 = /* @__PURE__ */ instanceOf(globalThis.URL, {
  typeConstructor: {
    _tag: "URL"
  },
  generation: {
    runtime: `Schema.URL`,
    Type: `globalThis.URL`
  },
  expected: "URL",
  toCodecJson: () => link()(URLString, urlFromString),
  toArbitrary: () => (fc) => fc.webUrl().map((s) => new globalThis.URL(s)),
  toEquivalence: () => (a, b) => a.toString() === b.toString()
});
var DateString = /* @__PURE__ */ String4.annotate({
  expected: "a string in ISO 8601 format that will be decoded as a Date"
});
var Date4 = /* @__PURE__ */ instanceOf(globalThis.Date, {
  typeConstructor: {
    _tag: "Date"
  },
  generation: {
    runtime: `Schema.Date`,
    Type: `globalThis.Date`
  },
  expected: "Date",
  toCodecJson: () => link()(DateString, dateFromString),
  toArbitrary: () => (fc, ctx) => fc.date(ctx?.constraints?.date)
});
var DateValid = /* @__PURE__ */ Date4.check(/* @__PURE__ */ isDateValid());
var Duration = /* @__PURE__ */ declare(isDuration, {
  typeConstructor: {
    _tag: "effect/Duration"
  },
  generation: {
    runtime: `Schema.Duration`,
    Type: `Duration.Duration`,
    importDeclaration: `import * as Duration from "effect/Duration"`
  },
  expected: "Duration",
  toCodecJson: () => link()(Union2([Struct({
    _tag: Literal2("Infinity")
  }), Struct({
    _tag: Literal2("NegativeInfinity")
  }), Struct({
    _tag: Literal2("Nanos"),
    value: BigInt5
  }), Struct({
    _tag: Literal2("Millis"),
    value: Int
  })]), transform2({
    decode: (e) => {
      switch (e._tag) {
        case "Infinity":
          return infinity;
        case "NegativeInfinity":
          return negativeInfinity;
        case "Nanos":
          return nanos(e.value);
        case "Millis":
          return millis(e.value);
      }
    },
    encode: (duration) => {
      switch (duration.value._tag) {
        case "Infinity":
          return {
            _tag: "Infinity"
          };
        case "NegativeInfinity":
          return {
            _tag: "NegativeInfinity"
          };
        case "Nanos":
          return {
            _tag: "Nanos",
            value: duration.value.nanos
          };
        case "Millis":
          return {
            _tag: "Millis",
            value: duration.value.millis
          };
      }
    }
  })),
  toArbitrary: () => (fc) => fc.oneof(fc.constant(infinity), fc.constant(negativeInfinity), fc.bigInt().map(nanos), fc.maxSafeInteger().map(millis)),
  toFormatter: () => globalThis.String,
  toEquivalence: () => Equivalence
});
var File = /* @__PURE__ */ instanceOf(globalThis.File, {
  typeConstructor: {
    _tag: "File"
  },
  generation: {
    runtime: `Schema.File`,
    Type: `globalThis.File`
  },
  expected: "File",
  toCodecJson: () => link()(Struct({
    data: String4.check(isBase64()),
    type: String4,
    name: String4,
    lastModified: Number5
  }), transformOrFail2({
    decode: (e) => match2(decodeBase64(e.data), {
      onFailure: (error) => fail5(new InvalidValue(some2(e.data), {
        message: error.message
      })),
      onSuccess: (bytes) => {
        const buffer = new globalThis.Uint8Array(bytes);
        return succeed5(new globalThis.File([buffer], e.name, {
          type: e.type,
          lastModified: e.lastModified
        }));
      }
    }),
    encode: (file) => tryPromise2({
      try: async () => {
        const bytes = new globalThis.Uint8Array(await file.arrayBuffer());
        return {
          data: encodeBase64(bytes),
          type: file.type,
          name: file.name,
          lastModified: file.lastModified
        };
      },
      catch: (e) => new InvalidValue(some2(file), {
        message: globalThis.String(e)
      })
    })
  }))
});
var FormData2 = /* @__PURE__ */ instanceOf(globalThis.FormData, {
  typeConstructor: {
    _tag: "FormData"
  },
  generation: {
    runtime: `Schema.FormData`,
    Type: `globalThis.FormData`
  },
  expected: "FormData",
  toCodecJson: () => link()(ArraySchema(Tuple([String4, Union2([Struct({
    _tag: tag("String"),
    value: String4
  }), Struct({
    _tag: tag("File"),
    value: File
  })])])), transformOrFail2({
    decode: (e) => {
      const out = new globalThis.FormData;
      for (const [key, entry] of e) {
        out.append(key, entry.value);
      }
      return succeed5(out);
    },
    encode: (formData) => {
      return succeed5(globalThis.Array.from(formData.entries()).map(([key, value3]) => {
        if (typeof value3 === "string") {
          return [key, {
            _tag: "String",
            value: value3
          }];
        } else {
          return [key, {
            _tag: "File",
            value: value3
          }];
        }
      }));
    }
  }))
});
var URLSearchParams2 = /* @__PURE__ */ instanceOf(globalThis.URLSearchParams, {
  typeConstructor: {
    _tag: "URLSearchParams"
  },
  generation: {
    runtime: `Schema.URLSearchParams`,
    Type: `globalThis.URLSearchParams`
  },
  expected: "URLSearchParams",
  toCodecJson: () => link()(String4.annotate({
    expected: "a query string that will be decoded as URLSearchParams"
  }), transform2({
    decode: (e) => new globalThis.URLSearchParams(e),
    encode: (params) => params.toString()
  }))
});
var Finite = /* @__PURE__ */ Number5.check(/* @__PURE__ */ isFinite());
var Int = /* @__PURE__ */ Number5.check(/* @__PURE__ */ isInt());
var Base64String = /* @__PURE__ */ String4.annotate({
  expected: "a base64 encoded string that will be decoded as Uint8Array",
  format: "byte",
  contentEncoding: "base64"
});
var Uint8Array2 = /* @__PURE__ */ instanceOf(globalThis.Uint8Array, {
  typeConstructor: {
    _tag: "Uint8Array"
  },
  generation: {
    runtime: `Schema.Uint8Array`,
    Type: `globalThis.Uint8Array`
  },
  expected: "Uint8Array",
  toCodecJson: () => link()(Base64String, uint8ArrayFromBase64String),
  toArbitrary: () => (fc) => fc.uint8Array()
});
var immerable = /* @__PURE__ */ globalThis.Symbol.for("immer-draftable");
function makeClass(Inherited, identifier2, struct2, annotations, proto) {
  const getClassSchema = getClassSchemaFactory(struct2, identifier2, annotations);
  const ClassTypeId2 = getClassTypeId(identifier2);
  const out = class extends Inherited {
    constructor(...[input, options]) {
      input = input ?? {};
      const validated = struct2.make(input, options);
      super({
        ...input,
        ...validated
      }, {
        ...options,
        disableChecks: true
      });
    }
    static [TypeId16] = TypeId16;
    get [ClassTypeId2]() {
      return ClassTypeId2;
    }
    static [immerable] = true;
    static identifier = identifier2;
    static fields = struct2.fields;
    static get ast() {
      return getClassSchema(this).ast;
    }
    static pipe() {
      return pipeArguments(this, arguments);
    }
    static rebuild(ast) {
      return getClassSchema(this).rebuild(ast);
    }
    static make(input, options) {
      return new this(input, options);
    }
    static makeOption(input, options) {
      return makeOption(getClassSchema(this))(input ?? {}, options);
    }
    static makeEffect(input, options) {
      return mapErrorEager2(makeEffect(getClassSchema(this))(input ?? {}, options), (issue) => new SchemaError(issue));
    }
    static annotate(annotations2) {
      return this.rebuild(annotate(this.ast, annotations2));
    }
    static annotateKey(annotations2) {
      return this.rebuild(annotateKey(this.ast, annotations2));
    }
    static check(...checks) {
      return this.rebuild(appendChecks(this.ast, checks));
    }
    static extend(identifier3) {
      return (newFields, annotations2) => {
        const fields = {
          ...struct2.fields,
          ...newFields
        };
        return makeClass(this, identifier3, makeStruct(struct(fields, struct2.ast.checks, {
          identifier: identifier3
        }), fields), annotations2, proto);
      };
    }
    static mapFields(f, options) {
      return struct2.mapFields(f, options);
    }
  };
  if (proto !== undefined) {
    Object.assign(out.prototype, proto(identifier2));
  }
  return out;
}
function getClassTransformation(self) {
  return new Transformation(transform((input) => new self(input)), passthrough2());
}
function getClassTypeId(identifier2) {
  return `~effect/Schema/Class/${identifier2}`;
}
function getClassSchemaFactory(from, identifier2, annotations) {
  let memo;
  return (self) => {
    if (memo === undefined) {
      const transformation = getClassTransformation(self);
      const to = make10(new Declaration([from.ast], () => (input, ast) => {
        return input instanceof self || hasProperty(input, getClassTypeId(identifier2)) ? succeed5(input) : fail5(new InvalidType(ast, some2(input)));
      }, {
        identifier: identifier2,
        [ClassTypeId]: ([from2]) => new Link(from2, transformation),
        toCodec: ([from2]) => new Link(from2.ast, transformation),
        toArbitrary: ([from2]) => () => from2.map((args2) => new self(args2)),
        toFormatter: ([from2]) => (t) => `${self.identifier}(${from2(t)})`,
        "~sentinels": collectSentinels(from.ast),
        ...annotations
      }));
      memo = from.pipe(decodeTo2(to, transformation));
    }
    return memo;
  };
}
function isStruct(schema) {
  return isSchema(schema);
}
var ErrorClass = (identifier2) => (schema, annotations) => {
  const struct2 = isStruct(schema) ? schema : Struct(schema);
  const self = makeClass(Error2, identifier2, struct2, annotations, (identifier3) => ({
    name: identifier3
  }));
  return self;
};
var TaggedErrorClass = (identifier2) => {
  return (tagValue, schema, annotations) => {
    return ErrorClass(identifier2 ?? tagValue)(isStruct(schema) ? schema.mapFields((fields) => ({
      _tag: tag(tagValue),
      ...fields
    }), {
      unsafePreserveChecks: true
    }) : TaggedStruct(tagValue, schema), annotations);
  };
};
function toCodecStringTree(schema, options) {
  return make10(toCodecEnsureArray(options?.keepDeclarations === true ? serializerStringTreeKeepDeclarations(schema.ast) : serializerStringTree(schema.ast)));
}
function getStringTreePriority(ast) {
  switch (ast._tag) {
    case "Null":
    case "Boolean":
    case "Number":
    case "BigInt":
    case "Symbol":
    case "UniqueSymbol":
      return 0;
    default:
      return 1;
  }
}
var treeReorder = /* @__PURE__ */ makeReorder(getStringTreePriority);
function serializerTree(ast, recur2, onMissingAnnotation) {
  switch (ast._tag) {
    case "Declaration": {
      const getLink = ast.annotations?.toCodecJson ?? ast.annotations?.toCodec;
      if (isFunction(getLink)) {
        const tps = isDeclaration(ast) ? ast.typeParameters.map((tp) => make10(recur2(toEncoded(tp)))) : [];
        const link2 = getLink(tps);
        const to = recur2(link2.to);
        return replaceEncoding(ast, to === link2.to ? [link2] : [new Link(to, link2.transformation)]);
      }
      return onMissingAnnotation(ast);
    }
    case "Null":
      return replaceEncoding(ast, [nullToString]);
    case "Boolean":
      return replaceEncoding(ast, [booleanToString]);
    case "Unknown":
    case "ObjectKeyword":
      return replaceEncoding(ast, [unknownToStringTree]);
    case "Enum":
    case "Number":
    case "Literal":
    case "UniqueSymbol":
    case "Symbol":
    case "BigInt":
      return ast.toCodecStringTree();
    case "Objects": {
      if (ast.propertySignatures.some((ps) => typeof ps.name !== "string")) {
        throw new globalThis.Error("Objects property names must be strings", {
          cause: ast
        });
      }
      return ast.recur(recur2);
    }
    case "Union": {
      const sortedTypes = treeReorder(ast.types);
      if (sortedTypes !== ast.types) {
        return new Union(sortedTypes, ast.mode, ast.annotations, ast.checks, ast.encoding, ast.context).recur(recur2);
      }
      return ast.recur(recur2);
    }
    case "Arrays":
    case "Suspend":
      return ast.recur(recur2);
  }
  return ast;
}
var nullToString = /* @__PURE__ */ new Link(/* @__PURE__ */ new Literal("null"), /* @__PURE__ */ new Transformation(/* @__PURE__ */ transform(() => null), /* @__PURE__ */ transform(() => "null")));
var booleanToString = /* @__PURE__ */ new Link(/* @__PURE__ */ new Union([/* @__PURE__ */ new Literal("true"), /* @__PURE__ */ new Literal("false")], "anyOf"), /* @__PURE__ */ new Transformation(/* @__PURE__ */ transform((s) => s === "true"), /* @__PURE__ */ String2()));
var serializerStringTree = /* @__PURE__ */ toCodec((ast) => {
  const out = serializerTree(ast, serializerStringTree, (ast2) => replaceEncoding(ast2, [unknownToUndefined]));
  if (out !== ast && isOptional(ast)) {
    return optionalKeyLastLink(out);
  }
  return out;
});
var unknownToUndefined = /* @__PURE__ */ new Link(undefined_3, /* @__PURE__ */ new Transformation(/* @__PURE__ */ passthrough2(), /* @__PURE__ */ transform(() => {
  return;
})));
var serializerStringTreeKeepDeclarations = /* @__PURE__ */ toCodec((ast) => {
  const out = serializerTree(ast, serializerStringTreeKeepDeclarations, identity);
  if (out !== ast && isOptional(ast)) {
    return optionalKeyLastLink(out);
  }
  return out;
});
var SERIALIZER_ENSURE_ARRAY = "~effect/Schema/SERIALIZER_ENSURE_ARRAY";
var toCodecEnsureArray = /* @__PURE__ */ toCodec((ast) => {
  if (isUnion(ast) && ast.annotations?.[SERIALIZER_ENSURE_ARRAY]) {
    return ast;
  }
  const out = onSerializerEnsureArray(ast);
  if (isArrays(out)) {
    const ensure = new Union([out, decodeTo(string2, out, new Transformation(split(), passthrough2()))], "anyOf", {
      [SERIALIZER_ENSURE_ARRAY]: true
    });
    return isOptional(ast) ? optionalKey(ensure) : ensure;
  }
  return out;
});
function onSerializerEnsureArray(ast) {
  switch (ast._tag) {
    default:
      return ast;
    case "Declaration":
    case "Arrays":
    case "Objects":
    case "Union":
    case "Suspend":
      return ast.recur(toCodecEnsureArray);
  }
}

// ../../packages/actions/dist/claude-code/schema.js
var hookEventNames = [
  "SessionStart",
  "Setup",
  "InstructionsLoaded",
  "UserPromptSubmit",
  "UserPromptExpansion",
  "PreToolUse",
  "PermissionRequest",
  "PostToolUse",
  "PostToolUseFailure",
  "PostToolBatch",
  "PermissionDenied",
  "Notification",
  "SubagentStart",
  "SubagentStop",
  "TaskCreated",
  "TaskCompleted",
  "Stop",
  "StopFailure",
  "TeammateIdle",
  "ConfigChange",
  "CwdChanged",
  "FileChanged",
  "WorktreeCreate",
  "WorktreeRemove",
  "PreCompact",
  "PostCompact",
  "SessionEnd",
  "Elicitation",
  "ElicitationResult"
];
var HookEventNameSchema = Literals(hookEventNames);
var HookPermissionModeSchema = Literals([
  "default",
  "plan",
  "acceptEdits",
  "auto",
  "dontAsk",
  "bypassPermissions"
]);
var hookEventBaseFields = {
  session_id: String4,
  transcript_path: String4,
  cwd: String4,
  permission_mode: optionalKey2(HookPermissionModeSchema)
};
var HookToolInputSchema = Record(String4, Unknown2);
var HookToolCallSchema = Struct({
  tool_name: String4,
  tool_input: HookToolInputSchema,
  tool_use_id: String4,
  tool_response: optionalKey2(Unknown2)
});
var HookPermissionDestinationSchema = Literals([
  "session",
  "userSettings",
  "projectSettings",
  "localSettings"
]);
var HookPermissionRuleSchema = Struct({
  toolName: String4,
  ruleContent: optionalKey2(String4)
});
var HookPermissionUpdateSchema = Union2([
  Struct({
    type: Literals(["addRules", "replaceRules", "removeRules"]),
    rules: ArraySchema(HookPermissionRuleSchema),
    behavior: Literals(["allow", "deny", "ask"]),
    destination: optionalKey2(HookPermissionDestinationSchema)
  }),
  Struct({
    type: Literal2("setMode"),
    mode: Literals(["default", "plan", "acceptEdits", "dontAsk", "bypassPermissions"]),
    destination: optionalKey2(HookPermissionDestinationSchema)
  }),
  Struct({
    type: Literals(["addDirectories", "removeDirectories"]),
    directories: ArraySchema(String4),
    destination: optionalKey2(HookPermissionDestinationSchema)
  })
]);
var SessionStartHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("SessionStart"),
  source: Literals(["startup", "resume", "clear", "compact"]),
  model: String4,
  agent_type: optionalKey2(String4)
});
var SetupHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("Setup"),
  trigger: Literals(["init", "maintenance"])
});
var InstructionsLoadedHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("InstructionsLoaded"),
  file_path: String4,
  memory_type: Literals(["User", "Project", "Local", "Managed"]),
  load_reason: Literals(["session_start", "nested_traversal", "path_glob_match", "include", "compact"]),
  globs: optionalKey2(ArraySchema(String4)),
  trigger_file_path: optionalKey2(String4),
  parent_file_path: optionalKey2(String4)
});
var UserPromptSubmitHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("UserPromptSubmit"),
  prompt: String4
});
var UserPromptExpansionHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("UserPromptExpansion"),
  expansion_type: Literals(["slash_command", "mcp_prompt"]),
  command_name: String4,
  command_args: String4,
  command_source: String4,
  prompt: String4
});
var PreToolUseHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PreToolUse"),
  tool_name: String4,
  tool_input: HookToolInputSchema,
  tool_use_id: String4
});
var PermissionRequestHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PermissionRequest"),
  tool_name: String4,
  tool_input: HookToolInputSchema,
  permission_suggestions: optionalKey2(ArraySchema(HookPermissionUpdateSchema))
});
var PostToolUseHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PostToolUse"),
  tool_name: String4,
  tool_input: HookToolInputSchema,
  tool_response: Unknown2,
  tool_use_id: String4,
  duration_ms: optionalKey2(Number5)
});
var PostToolUseFailureHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PostToolUseFailure"),
  tool_name: String4,
  tool_input: HookToolInputSchema,
  tool_use_id: String4,
  error: String4,
  is_interrupt: optionalKey2(Boolean2),
  duration_ms: optionalKey2(Number5)
});
var PostToolBatchHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PostToolBatch"),
  tool_calls: ArraySchema(HookToolCallSchema)
});
var PermissionDeniedHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PermissionDenied"),
  tool_name: String4,
  tool_input: HookToolInputSchema,
  tool_use_id: String4,
  reason: String4
});
var NotificationHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("Notification"),
  message: String4,
  title: optionalKey2(String4),
  notification_type: Literals([
    "permission_prompt",
    "idle_prompt",
    "auth_success",
    "elicitation_dialog",
    "elicitation_complete",
    "elicitation_response"
  ])
});
var SubagentStartHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("SubagentStart"),
  agent_id: String4,
  agent_type: String4
});
var SubagentStopHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("SubagentStop"),
  stop_hook_active: Boolean2,
  agent_id: String4,
  agent_type: String4,
  agent_transcript_path: String4,
  last_assistant_message: String4
});
var taskHookEventFields = {
  task_id: String4,
  task_subject: String4,
  task_description: optionalKey2(String4),
  teammate_name: optionalKey2(String4),
  team_name: optionalKey2(String4)
};
var TaskCreatedHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("TaskCreated"),
  ...taskHookEventFields
});
var TaskCompletedHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("TaskCompleted"),
  ...taskHookEventFields
});
var StopHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("Stop"),
  stop_hook_active: Boolean2,
  last_assistant_message: String4
});
var StopFailureHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("StopFailure"),
  error: Literals([
    "rate_limit",
    "authentication_failed",
    "oauth_org_not_allowed",
    "billing_error",
    "invalid_request",
    "server_error",
    "max_output_tokens",
    "unknown"
  ]),
  error_details: optionalKey2(String4),
  last_assistant_message: optionalKey2(String4)
});
var TeammateIdleHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("TeammateIdle"),
  teammate_name: String4,
  team_name: String4
});
var ConfigChangeHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("ConfigChange"),
  source: Literals([
    "user_settings",
    "project_settings",
    "local_settings",
    "policy_settings",
    "skills"
  ]),
  file_path: optionalKey2(String4)
});
var CwdChangedHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("CwdChanged"),
  old_cwd: String4,
  new_cwd: String4
});
var FileChangedHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("FileChanged"),
  file_path: String4,
  event: Literals(["change", "add", "unlink"])
});
var WorktreeCreateHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("WorktreeCreate"),
  name: String4,
  source_path: optionalKey2(String4)
});
var WorktreeRemoveHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("WorktreeRemove"),
  worktree_path: String4
});
var PreCompactHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PreCompact"),
  trigger: Literals(["manual", "auto"]),
  custom_instructions: String4
});
var PostCompactHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("PostCompact"),
  trigger: Literals(["manual", "auto"]),
  compact_summary: String4
});
var SessionEndHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("SessionEnd"),
  reason: Literals([
    "clear",
    "resume",
    "logout",
    "prompt_input_exit",
    "bypass_permissions_disabled",
    "other"
  ])
});
var ElicitationHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("Elicitation"),
  mcp_server_name: String4,
  message: String4,
  mode: optionalKey2(Literals(["form", "url"])),
  url: optionalKey2(String4),
  elicitation_id: optionalKey2(String4),
  requested_schema: optionalKey2(Unknown2)
});
var ElicitationResultHookEventSchema = Struct({
  ...hookEventBaseFields,
  hook_event_name: Literal2("ElicitationResult"),
  mcp_server_name: String4,
  action: Literals(["accept", "decline", "cancel"]),
  mode: optionalKey2(Literals(["form", "url"])),
  elicitation_id: optionalKey2(String4),
  content: optionalKey2(Record(String4, Unknown2))
});
var HookEventSchema = Union2([
  SessionStartHookEventSchema,
  SetupHookEventSchema,
  InstructionsLoadedHookEventSchema,
  UserPromptSubmitHookEventSchema,
  UserPromptExpansionHookEventSchema,
  PreToolUseHookEventSchema,
  PermissionRequestHookEventSchema,
  PostToolUseHookEventSchema,
  PostToolUseFailureHookEventSchema,
  PostToolBatchHookEventSchema,
  PermissionDeniedHookEventSchema,
  NotificationHookEventSchema,
  SubagentStartHookEventSchema,
  SubagentStopHookEventSchema,
  TaskCreatedHookEventSchema,
  TaskCompletedHookEventSchema,
  StopHookEventSchema,
  StopFailureHookEventSchema,
  TeammateIdleHookEventSchema,
  ConfigChangeHookEventSchema,
  CwdChangedHookEventSchema,
  FileChangedHookEventSchema,
  WorktreeCreateHookEventSchema,
  WorktreeRemoveHookEventSchema,
  PreCompactHookEventSchema,
  PostCompactHookEventSchema,
  SessionEndHookEventSchema,
  ElicitationHookEventSchema,
  ElicitationResultHookEventSchema
]);
var HookSpecificOutputSchema = Union2([
  Struct({
    hookEventName: Literals([
      "SessionStart",
      "Setup",
      "UserPromptSubmit",
      "UserPromptExpansion",
      "PostToolUse",
      "PostToolUseFailure",
      "PostToolBatch",
      "SubagentStart"
    ]),
    additionalContext: optionalKey2(String4),
    sessionTitle: optionalKey2(String4),
    updatedToolOutput: optionalKey2(Unknown2),
    updatedMCPToolOutput: optionalKey2(Unknown2)
  }),
  Struct({
    hookEventName: Literal2("PreToolUse"),
    permissionDecision: optionalKey2(Literals(["allow", "deny", "ask", "defer"])),
    permissionDecisionReason: optionalKey2(String4),
    updatedInput: optionalKey2(HookToolInputSchema),
    additionalContext: optionalKey2(String4)
  }),
  Struct({
    hookEventName: Literal2("PermissionRequest"),
    decision: optionalKey2(Struct({
      behavior: Literals(["allow", "deny"]),
      updatedInput: optionalKey2(HookToolInputSchema),
      updatedPermissions: optionalKey2(ArraySchema(HookPermissionUpdateSchema)),
      message: optionalKey2(String4),
      interrupt: optionalKey2(Boolean2)
    }))
  }),
  Struct({
    hookEventName: Literal2("PermissionDenied"),
    retry: optionalKey2(Boolean2)
  }),
  Struct({
    hookEventName: Literal2("WorktreeCreate"),
    worktreePath: String4
  }),
  Struct({
    hookEventName: Literals(["Elicitation", "ElicitationResult"]),
    action: Literals(["accept", "decline", "cancel"]),
    content: optionalKey2(Record(String4, Unknown2))
  })
]);
var HookEventOutputSchema = Struct({
  continue: optionalKey2(Boolean2),
  stopReason: optionalKey2(String4),
  decision: optionalKey2(Literal2("block")),
  reason: optionalKey2(String4),
  suppressOutput: optionalKey2(Boolean2),
  systemMessage: optionalKey2(String4),
  hookSpecificOutput: optionalKey2(HookSpecificOutputSchema),
  watchPaths: optionalKey2(ArraySchema(String4))
});
// ../../packages/actions/dist/helpers/apply-hook-event.js
import { basename } from "path";

// ../../packages/database/dist/client.js
import { Database as BunDatabase } from "bun:sqlite";
// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/entity.js
var entityKind = Symbol.for("drizzle:entityKind");
var hasOwnEntityKind = Symbol.for("drizzle:hasOwnEntityKind");
function is2(value3, type) {
  if (!value3 || typeof value3 !== "object")
    return false;
  if (value3 instanceof type)
    return true;
  if (!Object.prototype.hasOwnProperty.call(type, entityKind))
    throw new Error(`Class "${type.name ?? "<unknown>"}" doesn't look like a Drizzle entity. If this is incorrect and the class is provided by Drizzle, please report this as a bug.`);
  let cls = Object.getPrototypeOf(value3)?.constructor;
  if (cls)
    while (cls) {
      if (entityKind in cls && cls[entityKind] === type[entityKind])
        return true;
      cls = Object.getPrototypeOf(cls);
    }
  return false;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/column-common.js
var OriginalColumn = Symbol.for("drizzle:OriginalColumn");

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/column.js
var noop = (v) => v;
noop.isNoop = true;
var Column = class {
  static [entityKind] = "Column";
  codec;
  name;
  keyAsName;
  primary;
  notNull;
  default;
  defaultFn;
  onUpdateFn;
  hasDefault;
  isUnique;
  uniqueName;
  uniqueType;
  dataType;
  columnType;
  enumValues = undefined;
  generated = undefined;
  generatedIdentity = undefined;
  length;
  isLengthExact;
  isAlias;
  config;
  table;
  onInit() {}
  constructor(table, config) {
    this.config = config;
    this.onInit();
    this.table = table;
    this.name = config.name;
    this.isAlias = false;
    this.keyAsName = config.keyAsName;
    this.notNull = config.notNull;
    this.default = config.default;
    this.defaultFn = config.defaultFn;
    this.onUpdateFn = config.onUpdateFn;
    this.hasDefault = config.hasDefault;
    this.primary = config.primaryKey;
    this.isUnique = config.isUnique;
    this.uniqueName = config.uniqueName;
    this.uniqueType = config.uniqueType;
    this.dataType = config.dataType;
    this.columnType = config.columnType;
    this.generated = config.generated;
    this.generatedIdentity = config.generatedIdentity;
    this.length = config["length"];
    this.isLengthExact = config["isLengthExact"];
  }
  mapFromDriverValue = noop;
  mapToDriverValue = noop;
  postBuild() {
    return this;
  }
  shouldDisableInsert() {
    return this.config.generated !== undefined && this.config.generated.type !== "byDefault";
  }
  [OriginalColumn]() {
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/subquery.js
var Subquery = class {
  static [entityKind] = "Subquery";
  constructor(sql, fields, alias, isWith = false, usedTables = []) {
    this._ = {
      brand: "Subquery",
      sql,
      selectedFields: fields,
      alias,
      isWith,
      usedTables
    };
  }
};
var WithSubquery = class extends Subquery {
  static [entityKind] = "WithSubquery";
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/table.utils.js
var TableName = Symbol.for("drizzle:Name");

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/table.js
var TableSchema = Symbol.for("drizzle:Schema");
var TableColumns = Symbol.for("drizzle:Columns");
var ExtraConfigColumns = Symbol.for("drizzle:ExtraConfigColumns");
var OriginalName = Symbol.for("drizzle:OriginalName");
var BaseName = Symbol.for("drizzle:BaseName");
var IsAlias = Symbol.for("drizzle:IsAlias");
var ExtraConfigBuilder = Symbol.for("drizzle:ExtraConfigBuilder");
var IsDrizzleTable = Symbol.for("drizzle:IsDrizzleTable");
var Table = class {
  static [entityKind] = "Table";
  static Symbol = {
    Name: TableName,
    Schema: TableSchema,
    OriginalName,
    Columns: TableColumns,
    ExtraConfigColumns,
    BaseName,
    IsAlias,
    ExtraConfigBuilder
  };
  [TableName];
  [OriginalName];
  [TableSchema];
  [TableColumns];
  [ExtraConfigColumns];
  [BaseName];
  [IsAlias] = false;
  [IsDrizzleTable] = true;
  [ExtraConfigBuilder] = undefined;
  constructor(name, schema2, baseName) {
    this[TableName] = this[OriginalName] = name;
    this[TableSchema] = schema2;
    this[BaseName] = baseName;
  }
};
function getTableName(table) {
  return table[TableName];
}
function getTableUniqueName(table) {
  return `${table[TableSchema] ?? "public"}.${table[TableName]}`;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/tracing-utils.js
function iife(fn3, ...args2) {
  return fn3(...args2);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/tracing.js
var tracer3 = { startActiveSpan(name, fn3) {
  return fn3();
} };

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/view-common.js
var ViewBaseConfig = Symbol.for("drizzle:ViewBaseConfig");

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sql/sql.js
function isSQLWrapper(value3) {
  return value3 !== null && value3 !== undefined && typeof value3.getSQL === "function";
}
function mergeQueries(queries) {
  const result3 = {
    sql: "",
    params: []
  };
  for (const query of queries) {
    result3.sql += query.sql;
    result3.params.push(...query.params);
    if (query.typings?.length) {
      if (!result3.typings)
        result3.typings = [];
      result3.typings.push(...query.typings);
    }
  }
  return result3;
}
function _mergeQueries(queries) {
  const result3 = {
    sql: "",
    params: []
  };
  const sqls = [];
  for (const query of queries) {
    sqls.push(query.sql);
    result3.params.push(...query.params);
    if (query.typings?.length) {
      if (!result3.typings)
        result3.typings = [];
      result3.typings.push(...query.typings);
    }
  }
  result3._sql = Object.assign(sqls, { raw: sqls });
  return result3;
}
var StringChunk = class {
  static [entityKind] = "StringChunk";
  value;
  constructor(value3) {
    this.value = Array.isArray(value3) ? value3 : [value3];
  }
  getSQL() {
    return new SQL([this]);
  }
};
var SQL = class SQL2 {
  static [entityKind] = "SQL";
  decoder = noopDecoder;
  shouldInlineParams = false;
  usedTables = [];
  constructor(queryChunks) {
    this.queryChunks = queryChunks;
    for (const chunk of queryChunks)
      if (is2(chunk, Table)) {
        const schemaName = chunk[Table.Symbol.Schema];
        this.usedTables.push(schemaName === undefined ? chunk[Table.Symbol.Name] : schemaName + "." + chunk[Table.Symbol.Name]);
      }
  }
  append(query) {
    this.queryChunks.push(...query.queryChunks);
    return this;
  }
  toQuery(config) {
    return tracer3.startActiveSpan("drizzle.buildSQL", (span2) => {
      const query = this.buildQueryFromSourceParams(this.queryChunks, config);
      span2?.setAttributes({
        "drizzle.query.text": query.sql,
        "drizzle.query.params": JSON.stringify(query.params)
      });
      return query;
    });
  }
  buildQueryFromSourceParams(chunks, _config) {
    const config = Object.assign({}, _config, {
      inlineParams: _config.inlineParams || this.shouldInlineParams,
      paramStartIndex: _config.paramStartIndex || { value: 0 }
    });
    const { escapeName, escapeParam, prepareTyping, codecs, inlineParams, paramStartIndex, invokeSource } = config;
    const mappedChunks = chunks.map((chunk) => {
      if (is2(chunk, StringChunk))
        return {
          sql: chunk.value.join(""),
          params: []
        };
      if (is2(chunk, Name))
        return {
          sql: escapeName(chunk.value),
          params: []
        };
      if (chunk === undefined)
        return {
          sql: "",
          params: []
        };
      if (Array.isArray(chunk)) {
        const result3 = [new StringChunk("(")];
        for (const [i, p] of chunk.entries()) {
          result3.push(p);
          if (i < chunk.length - 1)
            result3.push(new StringChunk(", "));
        }
        result3.push(new StringChunk(")"));
        return this.buildQueryFromSourceParams(result3, config);
      }
      if (is2(chunk, SQL2))
        return this.buildQueryFromSourceParams(chunk.queryChunks, {
          ...config,
          inlineParams: inlineParams || chunk.shouldInlineParams
        });
      if (is2(chunk, Table)) {
        const schemaName = chunk[Table.Symbol.Schema];
        const tableName = chunk[Table.Symbol.Name];
        if (invokeSource === "mssql-view-with-schemabinding")
          return {
            sql: (schemaName === undefined ? escapeName("dbo") : escapeName(schemaName)) + "." + escapeName(tableName),
            params: []
          };
        return {
          sql: schemaName === undefined || chunk[IsAlias] ? escapeName(tableName) : escapeName(schemaName) + "." + escapeName(tableName),
          params: []
        };
      }
      if (is2(chunk, Column)) {
        const columnName = chunk.name;
        if (_config.invokeSource === "indexes")
          return {
            sql: escapeName(columnName),
            params: []
          };
        const schemaName = invokeSource === "mssql-check" ? undefined : chunk.table[Table.Symbol.Schema];
        return {
          sql: chunk.isAlias ? escapeName(chunk.name) : chunk.table[IsAlias] || schemaName === undefined ? escapeName(chunk.table[Table.Symbol.Name]) + "." + escapeName(columnName) : escapeName(schemaName) + "." + escapeName(chunk.table[Table.Symbol.Name]) + "." + escapeName(columnName),
          params: []
        };
      }
      if (is2(chunk, View)) {
        const schemaName = chunk[ViewBaseConfig].schema;
        const viewName = chunk[ViewBaseConfig].name;
        return {
          sql: schemaName === undefined || chunk[ViewBaseConfig].isAlias ? escapeName(viewName) : escapeName(schemaName) + "." + escapeName(viewName),
          params: []
        };
      }
      if (is2(chunk, Param)) {
        if (is2(chunk.value, SQL2))
          return this.buildQueryFromSourceParams([chunk.value], config);
        const useCodecs = codecs && is2(chunk.encoder, Column);
        if (is2(chunk.value, Placeholder)) {
          const escaped2 = escapeParam(paramStartIndex.value++, chunk);
          chunk.codec = useCodecs ? (value3) => codecs.apply(chunk.encoder, "normalizeParam", value3) : undefined;
          return {
            sql: useCodecs ? codecs.apply(chunk.encoder, "castParam", escaped2) : escaped2,
            params: [chunk],
            typings: ["none"]
          };
        }
        let mappedValue;
        if (chunk.value === null)
          mappedValue = chunk.value;
        else {
          mappedValue = chunk.encoder.mapToDriverValue.isNoop ? chunk.value : chunk.encoder.mapToDriverValue(chunk.value);
          if (is2(mappedValue, SQL2))
            return this.buildQueryFromSourceParams([mappedValue], config);
          if (useCodecs)
            mappedValue = codecs.apply(chunk.encoder, "normalizeParam", mappedValue);
        }
        if (inlineParams)
          return {
            sql: this.mapInlineParam(mappedValue, config),
            params: []
          };
        let typings = ["none"];
        if (prepareTyping)
          typings = [prepareTyping(chunk.encoder)];
        const escaped = escapeParam(paramStartIndex.value++, mappedValue);
        return {
          sql: useCodecs ? codecs.apply(chunk.encoder, "castParam", escaped) : escaped,
          params: [mappedValue],
          typings
        };
      }
      if (is2(chunk, Placeholder))
        return {
          sql: escapeParam(paramStartIndex.value++, chunk),
          params: [chunk],
          typings: ["none"]
        };
      if (is2(chunk, SQL2.Aliased) && chunk.fieldAlias !== undefined)
        return {
          sql: (chunk.origin !== undefined ? escapeName(chunk.origin) + "." : "") + escapeName(chunk.fieldAlias),
          params: []
        };
      if (is2(chunk, Subquery)) {
        if (chunk._.isWith)
          return {
            sql: escapeName(chunk._.alias),
            params: []
          };
        return this.buildQueryFromSourceParams([
          new StringChunk("("),
          chunk._.sql,
          new StringChunk(") "),
          new Name(chunk._.alias)
        ], config);
      }
      if (typeof chunk === "function" && "enumName" in chunk) {
        if ("schema" in chunk && chunk.schema)
          return {
            sql: escapeName(chunk.schema) + "." + escapeName(chunk.enumName),
            params: []
          };
        return {
          sql: escapeName(chunk.enumName),
          params: []
        };
      }
      if (isSQLWrapper(chunk)) {
        if (chunk.shouldOmitSQLParens?.())
          return this.buildQueryFromSourceParams([chunk.getSQL()], config);
        return this.buildQueryFromSourceParams([
          new StringChunk("("),
          chunk.getSQL(),
          new StringChunk(")")
        ], config);
      }
      if (inlineParams)
        return {
          sql: this.mapInlineParam(chunk, config),
          params: []
        };
      return {
        sql: escapeParam(paramStartIndex.value++, chunk),
        params: [chunk],
        typings: ["none"]
      };
    });
    if (_config.tagged)
      return _mergeQueries(mappedChunks);
    return mergeQueries(mappedChunks);
  }
  mapInlineParam(chunk, { escapeString }) {
    if (chunk === null)
      return "null";
    if (typeof chunk === "number" || typeof chunk === "boolean" || typeof chunk === "bigint")
      return chunk.toString();
    if (typeof chunk === "string")
      return escapeString(chunk);
    if (typeof chunk === "object") {
      const mappedValueAsString = chunk.toString();
      if (mappedValueAsString === "[object Object]")
        return escapeString(JSON.stringify(chunk));
      return escapeString(mappedValueAsString);
    }
    throw new Error("Unexpected param value: " + chunk);
  }
  getSQL() {
    return this;
  }
  as(alias) {
    if (alias === undefined)
      return this;
    return new SQL2.Aliased(this, alias);
  }
  mapWith(decoder) {
    this.decoder = typeof decoder === "function" ? { mapFromDriverValue: decoder } : decoder;
    return this;
  }
  inlineParams() {
    this.shouldInlineParams = true;
    return this;
  }
  if(condition) {
    return condition ? this : undefined;
  }
};
var Name = class {
  static [entityKind] = "Name";
  brand;
  constructor(value3) {
    this.value = value3;
  }
  getSQL() {
    return new SQL([this]);
  }
};
function isDriverValueEncoder(value3) {
  return typeof value3 === "object" && value3 !== null && "mapToDriverValue" in value3 && typeof value3.mapToDriverValue === "function";
}
var noopDecoder = { mapFromDriverValue: (value3) => value3 };
noopDecoder.mapFromDriverValue.isNoop = true;
var noopEncoder = { mapToDriverValue: (value3) => value3 };
noopEncoder.mapToDriverValue.isNoop = true;
var noopMapper = {
  ...noopDecoder,
  ...noopEncoder
};
var Param = class {
  static [entityKind] = "Param";
  brand;
  constructor(value3, encoder2 = noopEncoder, codec) {
    this.value = value3;
    this.encoder = encoder2;
    this.codec = codec;
  }
  getSQL() {
    return new SQL([this]);
  }
};
function sql(strings, ...params) {
  const queryChunks = [];
  if (params.length > 0 || strings.length > 0 && strings[0] !== "")
    queryChunks.push(new StringChunk(strings[0]));
  for (const [paramIndex, param] of params.entries())
    queryChunks.push(param, new StringChunk(strings[paramIndex + 1]));
  return new SQL(queryChunks);
}
(function(_sql) {
  function empty4() {
    return new SQL([]);
  }
  _sql.empty = empty4;
  function fromList(list) {
    return new SQL(list);
  }
  _sql.fromList = fromList;
  function raw(str) {
    return new SQL([new StringChunk(str)]);
  }
  _sql.raw = raw;
  function join(chunks, separator) {
    const result3 = [];
    for (const [i, chunk] of chunks.entries()) {
      if (i > 0 && separator !== undefined)
        result3.push(separator);
      result3.push(chunk);
    }
    return new SQL(result3);
  }
  _sql.join = join;
  function identifier2(value3) {
    return new Name(value3);
  }
  _sql.identifier = identifier2;
  function placeholder(name) {
    return new Placeholder(name);
  }
  _sql.placeholder = placeholder;
  function param(value3, encoder2) {
    return new Param(value3, encoder2);
  }
  _sql.param = param;
  function comment(input) {
    const encoded = sqlCommenter(input);
    if (!encoded.length)
      return;
    return sql.raw(encoded);
  }
  _sql.comment = comment;
})(sql || (sql = {}));
function sqlCommenter(input) {
  const encoded = sqlCommenter.encodeInput(input);
  if (!encoded.length)
    return "";
  return `/*${encoded}*/`;
}
(function(_sqlCommenter) {
  function merge3(input1, input2) {
    let encoded;
    if (typeof input1 === "object" && typeof input2 === "object")
      encoded = encodeInput({
        ...input1,
        ...input2
      });
    else if (input1 && input2)
      encoded = [encodeInput(input1), encodeInput(input2)].filter((i) => i.length).join(",");
    else if (input2)
      encoded = encodeInput(input2);
    else if (input1)
      encoded = encodeInput(input1);
    else
      return "";
    if (!encoded.length)
      return "";
    return `/*${encoded}*/`;
  }
  _sqlCommenter.merge = merge3;
  function encodeInput(input) {
    if (typeof input === "string") {
      if (!input.length)
        return input;
      return sanitizeStringInput(input);
    }
    const parts = [];
    for (const [key, value3] of Object.entries(input)) {
      if (value3 === null || value3 === undefined || value3 === "")
        continue;
      const encodedKey = sanitizeObjectElement(key);
      const encodedValue = sanitizeObjectElement(String(value3));
      parts.push(`${encodedKey}='${encodedValue}'`);
    }
    if (!parts.length)
      return "";
    return parts.sort().join(",");
  }
  _sqlCommenter.encodeInput = encodeInput;
  function sanitizeObjectElement(key) {
    return encodeURIComponent(key).replace(/'/g, `\\'`);
  }
  _sqlCommenter.sanitizeObjectElement = sanitizeObjectElement;
  function sanitizeStringInput(input) {
    return input.replace(/\/\*/g, "/ *").replace(/\*\//g, "* /");
  }
  _sqlCommenter.sanitizeStringInput = sanitizeStringInput;
})(sqlCommenter || (sqlCommenter = {}));
(function(_SQL) {

  class Aliased {
    static [entityKind] = "SQL.Aliased";
    isSelectionField = false;
    origin;
    constructor(sql2, fieldAlias) {
      this.sql = sql2;
      this.fieldAlias = fieldAlias;
    }
    getSQL() {
      return this.sql;
    }
    clone() {
      return new Aliased(this.sql, this.fieldAlias);
    }
  }
  _SQL.Aliased = Aliased;
})(SQL || (SQL = {}));
var Placeholder = class {
  static [entityKind] = "Placeholder";
  constructor(name) {
    this.name = name;
  }
  getSQL() {
    return new SQL([this]);
  }
};
function fillPlaceholders(params, values) {
  return params.map((p) => {
    if (is2(p, Placeholder)) {
      if (!(p.name in values))
        throw new Error(`No value for placeholder "${p.name}" was provided`);
      return values[p.name];
    }
    if (is2(p, Param) && is2(p.value, Placeholder)) {
      if (!(p.value.name in values))
        throw new Error(`No value for placeholder "${p.value.name}" was provided`);
      if (values[p.value.name] === null)
        return values[p.value.name];
      const mapped = p.encoder.mapToDriverValue.isNoop ? values[p.value.name] : p.encoder.mapToDriverValue(values[p.value.name]);
      return p.codec ? p.codec(mapped) : mapped;
    }
    return p;
  });
}
var IsDrizzleView = Symbol.for("drizzle:IsDrizzleView");
var View = class {
  static [entityKind] = "View";
  [ViewBaseConfig];
  [IsDrizzleView] = true;
  get [TableName]() {
    return this[ViewBaseConfig].name;
  }
  get [TableSchema]() {
    return this[ViewBaseConfig].schema;
  }
  get [IsAlias]() {
    return this[ViewBaseConfig].isAlias;
  }
  get [OriginalName]() {
    return this[ViewBaseConfig].originalName;
  }
  get [TableColumns]() {
    return this[ViewBaseConfig].selectedFields;
  }
  constructor({ name, schema: schema2, selectedFields, query }) {
    this[ViewBaseConfig] = {
      name,
      originalName: name,
      schema: schema2,
      selectedFields,
      query,
      isExisting: !query,
      isAlias: false
    };
  }
};
Column.prototype.getSQL = function() {
  return new SQL([this]);
};
Subquery.prototype.getSQL = function() {
  return new SQL([this]);
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/utils.js
function mapResultRow(columns, row, joinsNotNullableMap) {
  const nullifyMap = {};
  const result3 = columns.reduce((result4, { path, field, codec, arrayDimensions }, columnIndex) => {
    let decoder;
    if (is2(field, Column))
      decoder = field;
    else if (is2(field, SQL))
      decoder = field.decoder;
    else if (is2(field, Subquery))
      decoder = field._.sql.decoder;
    else
      decoder = field.sql.decoder;
    let node = result4;
    for (const [pathChunkIndex, pathChunk] of path.entries())
      if (pathChunkIndex < path.length - 1) {
        if (!(pathChunk in node))
          node[pathChunk] = {};
        node = node[pathChunk];
      } else {
        const rawValue = row[columnIndex];
        const value3 = node[pathChunk] = rawValue === null ? null : decoder.mapFromDriverValue(codec ? codec(rawValue, arrayDimensions) : rawValue);
        if (joinsNotNullableMap && is2(field, Column) && path.length === 2) {
          const objectName = path[0];
          if (!(objectName in nullifyMap))
            nullifyMap[objectName] = value3 === null ? getTableName(field.table) : false;
          else if (typeof nullifyMap[objectName] === "string" && nullifyMap[objectName] !== getTableName(field.table))
            nullifyMap[objectName] = false;
        }
      }
    return result4;
  }, {});
  if (joinsNotNullableMap && Object.keys(nullifyMap).length > 0) {
    for (const [objectName, tableName] of Object.entries(nullifyMap))
      if (typeof tableName === "string" && !joinsNotNullableMap[tableName])
        result3[objectName] = null;
  }
  return result3;
}
var FnConstructor = Object.getPrototypeOf(() => null).constructor;
function makeJitQueryMapperInner(columns, joinsNotNullableMap = {}) {
  const preFn = [];
  const fn3 = [];
  fn3.push(`const [ ${columns.map((_, i) => `c${i}`).join(", ")} ] = rows[i];`);
  const nullifyMap = {};
  const objectIds = {};
  const decodes = Array.from({ length: columns.length });
  for (let idx = 0;idx < columns.length; ++idx) {
    const { field, path, codec, arrayDimensions } = columns[idx];
    let decoder;
    let decoderStr;
    let decoderFieldDestructure;
    let isColumn = false;
    if (is2(field, Column)) {
      isColumn = true;
      decoder = field;
      decoderFieldDestructure = `field: decoder${idx}`;
    } else if (is2(field, SQL)) {
      decoder = field.decoder;
      decoderFieldDestructure = `field: { decoder: decoder${idx} }`;
    } else if (is2(field, Subquery)) {
      decoder = field._.sql.decoder;
      decoderFieldDestructure = `field: { _: { sql: { decoder: decoder${idx} } } }`;
    } else {
      decoder = field.sql.decoder;
      decoderFieldDestructure = `field: { sql: { decoder: decoder${idx} } }`;
    }
    decoderStr = `decoder${idx}.mapFromDriverValue`;
    if (decoder.mapFromDriverValue.isNoop)
      decoderStr = "";
    if (decoderStr)
      preFn.push(`const { ${decoderFieldDestructure}${codec ? `, codec: codec${idx}` : ""} } = columns[${idx}];`);
    else if (codec)
      preFn.push(`const { codec: codec${idx} } = columns[${idx}];`);
    const colStr = `c${idx}`;
    let decodedValue = colStr;
    if (codec)
      decodedValue = `codec${idx}(${decodedValue}, ${arrayDimensions})`;
    if (decoderStr)
      decodedValue = `${decoderStr}(${decodedValue})`;
    decodes[idx] = colStr === decodedValue ? `${colStr}` : `${colStr} === null ? ${colStr} : ${decodedValue}`;
    if (path.length !== 2 || !isColumn)
      continue;
    if (objectIds[path[0]] === undefined)
      objectIds[path[0]] = [`c${idx}`];
    else
      objectIds[path[0]]?.push(`c${idx}`);
    const [objectName] = path;
    const tableName = getTableName(field.table);
    nullifyMap[objectName] = joinsNotNullableMap[tableName] ? false : typeof nullifyMap[objectName] === "string" ? nullifyMap[objectName] === tableName ? tableName : false : tableName;
  }
  fn3.push(`mapped[i] = {`);
  let currentObjectPath = [];
  for (let idx = 0;idx < columns.length; ++idx) {
    const { path } = columns[idx];
    const jsonPath = path.map((e) => JSON.stringify(e));
    const decodedValue = decodes[idx];
    const objectPath = path.slice(0, -1);
    let commonLen = 0;
    while (commonLen < currentObjectPath.length && commonLen < objectPath.length && currentObjectPath[commonLen] === objectPath[commonLen])
      commonLen++;
    for (let d = currentObjectPath.length - 1;d >= commonLen; --d)
      fn3.push(`${"\t".repeat(d + 1)}},`);
    for (let d = commonLen;d < objectPath.length; ++d)
      fn3.push(`${"\t".repeat(d + 1)}${jsonPath[d]}: ${d === 0 && objectPath.length === 1 && typeof nullifyMap[path[0]] === "string" ? `${objectIds[path[0]]?.map((c) => `${c} === null`).join(" && ")} ? null : {` : "{"}`);
    currentObjectPath = objectPath;
    fn3.push(`${"\t".repeat(path.length)}${jsonPath[path.length - 1]}: ${decodedValue},`);
  }
  for (let d = currentObjectPath.length - 1;d >= 0; --d)
    fn3.push(`${"\t".repeat(d + 1)}},`);
  fn3.push(`};`);
  return `${preFn.length ? `${preFn.join(`
	`)}
	` : ""}for (let i = 0; i < length; ++i) {
		${fn3.join(`
		`)}
	}`;
}
function makeJitQueryMapper(columns, joinsNotNullableMap) {
  const internals = `	"use strict";
	const { columns } = this;
	const { length } = rows;
	const mapped = Array.from({ length });
	${makeJitQueryMapperInner(columns, joinsNotNullableMap)}
	return mapped;
	//# sourceURL=drizzle:jit-query-mapper`;
  return Object.assign(new FnConstructor("rows", internals).bind({ columns }), { body: `function jitQueryMapper (rows) {
${internals}
}` });
}
function jitCompatCheck(isEnabled) {
  if (!isEnabled)
    return false;
  try {
    const res = new FnConstructor("input", '"use strict"; return input;')(true);
    if (res !== true) {
      console.warn(`Unable to use jit mappers due to incompatibility: corrupted jit function output.
Falling back to premade mappers.
Error details:`);
      console.error(`Expected to receive \`true\`, got: ${res}`);
    }
    return true;
  } catch (e) {
    console.warn(`Unable to use jit mappers due to incompatibility.
Falling back to premade mappers.
Error details:`);
    console.error(e);
    return false;
  }
}
function orderSelectedFields(fields, pathPrefix, codecs) {
  return Object.entries(fields).reduce((result3, [name, field]) => {
    if (typeof name !== "string")
      return result3;
    const newPath = pathPrefix ? [...pathPrefix, name] : [name];
    if (is2(field, Column))
      result3.push({
        path: newPath,
        field,
        codec: codecs?.get(field, "normalize"),
        arrayDimensions: field.dimensions
      });
    else if (is2(field, Column) || is2(field, SQL) || is2(field, SQL.Aliased) || is2(field, Subquery))
      result3.push({
        path: newPath,
        field
      });
    else if (is2(field, Table))
      result3.push(...orderSelectedFields(field[Table.Symbol.Columns], newPath, codecs));
    else
      result3.push(...orderSelectedFields(field, newPath, codecs));
    return result3;
  }, []);
}
function haveSameKeys(left, right) {
  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  if (leftKeys.length !== rightKeys.length)
    return false;
  for (const [index, key] of leftKeys.entries())
    if (key !== rightKeys[index])
      return false;
  return true;
}
function mapUpdateSet(table, values) {
  const entries = Object.entries(values).filter(([, value3]) => value3 !== undefined).map(([key, value3]) => {
    if (is2(value3, SQL) || is2(value3, Column))
      return [key, value3];
    else
      return [key, new Param(value3, table[Table.Symbol.Columns][key])];
  });
  if (entries.length === 0)
    throw new Error("No values to set");
  return Object.fromEntries(entries);
}
function applyMixins(baseClass, extendedClasses) {
  for (const extendedClass of extendedClasses)
    for (const name of Object.getOwnPropertyNames(extendedClass.prototype)) {
      if (name === "constructor")
        continue;
      Object.defineProperty(baseClass.prototype, name, Object.getOwnPropertyDescriptor(extendedClass.prototype, name) || Object.create(null));
    }
}
function getTableColumns(table) {
  return table[Table.Symbol.Columns];
}
function getTableLikeName(table) {
  return is2(table, Subquery) ? table._.alias : is2(table, View) ? table[ViewBaseConfig].name : is2(table, SQL) ? undefined : table[Table.Symbol.IsAlias] ? table[Table.Symbol.Name] : table[Table.Symbol.BaseName];
}
function getColumnNameAndConfig(a, b) {
  return {
    name: typeof a === "string" && a.length > 0 ? a : "",
    config: typeof a === "object" ? a : b
  };
}
var textDecoder = typeof TextDecoder === "undefined" ? null : new TextDecoder;
var CONSTANTS = {
  INT8_MIN: -128,
  INT8_MAX: 127,
  INT8_UNSIGNED_MAX: 255,
  INT16_MIN: -32768,
  INT16_MAX: 32767,
  INT16_UNSIGNED_MAX: 65535,
  INT24_MIN: -8388608,
  INT24_MAX: 8388607,
  INT24_UNSIGNED_MAX: 16777215,
  INT32_MIN: -2147483648,
  INT32_MAX: 2147483647,
  INT32_UNSIGNED_MAX: 4294967295,
  INT48_MIN: -140737488355328,
  INT48_MAX: 140737488355327,
  INT48_UNSIGNED_MAX: 281474976710655,
  INT64_MIN: -9223372036854775808n,
  INT64_MAX: 9223372036854775807n,
  INT64_UNSIGNED_MAX: 18446744073709551615n
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/logger.js
var ConsoleLogWriter = class {
  static [entityKind] = "ConsoleLogWriter";
  write(message) {
    console.log(message);
  }
};
var DefaultLogger = class {
  static [entityKind] = "DefaultLogger";
  writer;
  constructor(config) {
    this.writer = config?.writer ?? new ConsoleLogWriter;
  }
  logQuery(query, params) {
    const stringifiedParams = params.map((p) => {
      try {
        return JSON.stringify(p);
      } catch {
        return String(p);
      }
    });
    const paramsStr = stringifiedParams.length ? ` -- params: [${stringifiedParams.join(", ")}]` : "";
    this.writer.write(`Query: ${query}${paramsStr}`);
  }
};
var NoopLogger = class {
  static [entityKind] = "NoopLogger";
  logQuery() {}
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/alias.js
var ColumnTableAliasProxyHandler = class {
  static [entityKind] = "ColumnTableAliasProxyHandler";
  constructor(table, ignoreColumnAlias) {
    this.table = table;
    this.ignoreColumnAlias = ignoreColumnAlias;
  }
  get(columnObj, prop) {
    if (prop === "table")
      return this.table;
    if (prop === "isAlias" && this.ignoreColumnAlias)
      return false;
    return columnObj[prop];
  }
};
var ViewSelectionAliasProxyHandler = class {
  static [entityKind] = "ViewSelectionAliasProxyHandler";
  constructor(view, selection, ignoreColumnAlias) {
    this.view = view;
    this.selection = selection;
    this.ignoreColumnAlias = ignoreColumnAlias;
  }
  get(selection, prop) {
    const value3 = selection[prop];
    if (is2(value3, Column))
      return new Proxy(value3, new ColumnTableAliasProxyHandler(this.view, this.ignoreColumnAlias));
    if (is2(value3, Subquery) || is2(value3, SQL) || is2(value3, SQL.Aliased) || isSQLWrapper(value3) || typeof value3 !== "object" || value3 === null)
      return value3;
    return new Proxy(value3, this);
  }
};
var TableAliasProxyHandler = class {
  static [entityKind] = "TableAliasProxyHandler";
  constructor(alias, replaceOriginalName, ignoreColumnAlias) {
    this.alias = alias;
    this.replaceOriginalName = replaceOriginalName;
    this.ignoreColumnAlias = ignoreColumnAlias;
  }
  get(target, prop) {
    if (prop === Table.Symbol.IsAlias)
      return true;
    if (prop === Table.Symbol.Name)
      return this.alias;
    if (this.replaceOriginalName && prop === Table.Symbol.OriginalName)
      return this.alias;
    if (prop === ViewBaseConfig)
      return {
        ...target[ViewBaseConfig],
        name: this.alias,
        isAlias: true,
        selectedFields: new Proxy(target[ViewBaseConfig].selectedFields, new ViewSelectionAliasProxyHandler(new Proxy(target, this), target[ViewBaseConfig].selectedFields, this.ignoreColumnAlias))
      };
    if (prop === Table.Symbol.Columns) {
      const columns = target[Table.Symbol.Columns];
      if (!columns)
        return columns;
      if (is2(target, View))
        return new Proxy(target[Table.Symbol.Columns], new ViewSelectionAliasProxyHandler(new Proxy(target, this), target[Table.Symbol.Columns], this.ignoreColumnAlias));
      const proxiedColumns = {};
      Object.keys(columns).map((key) => {
        proxiedColumns[key] = new Proxy(columns[key], new ColumnTableAliasProxyHandler(new Proxy(target, this), this.ignoreColumnAlias));
      });
      return proxiedColumns;
    }
    const value3 = target[prop];
    if (is2(value3, Column))
      return new Proxy(value3, new ColumnTableAliasProxyHandler(new Proxy(target, this), this.ignoreColumnAlias));
    return value3;
  }
};
var ColumnAliasProxyHandler = class {
  static [entityKind] = "ColumnAliasProxyHandler";
  constructor(alias) {
    this.alias = alias;
  }
  get(target, prop) {
    if (prop === "isAlias")
      return true;
    if (prop === "name")
      return this.alias;
    if (prop === "keyAsName")
      return false;
    if (prop === OriginalColumn)
      return () => target;
    return target[prop];
  }
};
function aliasedTable(table, tableAlias) {
  return new Proxy(table, new TableAliasProxyHandler(tableAlias, false, false));
}
function aliasedColumn(column, alias) {
  return new Proxy(column, new ColumnAliasProxyHandler(alias));
}
function aliasedTableColumn(column, tableAlias) {
  return new Proxy(column, new ColumnTableAliasProxyHandler(new Proxy(column.table, new TableAliasProxyHandler(tableAlias, false, false)), false));
}
function mapColumnsInAliasedSQLToAlias(query, alias) {
  return new SQL.Aliased(mapColumnsInSQLToAlias(query.sql, alias), query.fieldAlias);
}
function mapColumnsInSQLToAlias(query, alias) {
  return sql.join(query.queryChunks.map((c) => {
    if (is2(c, Column))
      return aliasedTableColumn(c, alias);
    if (is2(c, SQL))
      return mapColumnsInSQLToAlias(c, alias);
    if (is2(c, SQL.Aliased))
      return mapColumnsInAliasedSQLToAlias(c, alias);
    return c;
  }));
}
Column.prototype.as = function(alias) {
  return aliasedColumn(this, alias);
};
function getOriginalColumnFromAlias(column) {
  return column[OriginalColumn]();
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/errors.js
var DrizzleError = class extends Error {
  static [entityKind] = "DrizzleError";
  constructor({ message, cause }) {
    super(message);
    this.name = "DrizzleError";
    this.cause = cause;
  }
};
var DrizzleQueryError = class DrizzleQueryError2 extends Error {
  static [entityKind] = "DrizzleQueryError";
  constructor(query, params, cause) {
    super(`Failed query: ${query}
params: ${params}`);
    this.query = query;
    this.params = params;
    this.cause = cause;
    Error.captureStackTrace(this, DrizzleQueryError2);
    if (cause)
      this.cause = cause;
  }
};
var TransactionRollbackError = class extends DrizzleError {
  static [entityKind] = "TransactionRollbackError";
  constructor() {
    super({ message: "Rollback" });
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sql/expressions/conditions.js
function bindIfParam(value3, column) {
  if (isDriverValueEncoder(column) && !isSQLWrapper(value3) && !is2(value3, Param) && !is2(value3, Placeholder) && !is2(value3, Column) && !is2(value3, Table) && !is2(value3, View))
    return new Param(value3, column);
  return value3;
}
var eq = (left, right) => {
  return sql`${left} = ${bindIfParam(right, left)}`;
};
var ne = (left, right) => {
  return sql`${left} <> ${bindIfParam(right, left)}`;
};
function and(...unfilteredConditions) {
  const conditions = unfilteredConditions.filter((c) => c !== undefined);
  if (conditions.length === 0)
    return;
  if (conditions.length === 1)
    return new SQL(conditions);
  return new SQL([
    new StringChunk("("),
    sql.join(conditions.map((c) => sql`(${c})`), new StringChunk(" and ")),
    new StringChunk(")")
  ]);
}
function or(...unfilteredConditions) {
  const conditions = unfilteredConditions.filter((c) => c !== undefined);
  if (conditions.length === 0)
    return;
  if (conditions.length === 1)
    return new SQL(conditions);
  return new SQL([
    new StringChunk("("),
    sql.join(conditions.map((c) => sql`(${c})`), new StringChunk(" or ")),
    new StringChunk(")")
  ]);
}
function not(condition) {
  return is2(condition, SQL) ? sql`not (${condition})` : sql`not ${condition}`;
}
var gt = (left, right) => {
  return sql`${left} > ${bindIfParam(right, left)}`;
};
var gte = (left, right) => {
  return sql`${left} >= ${bindIfParam(right, left)}`;
};
var lt = (left, right) => {
  return sql`${left} < ${bindIfParam(right, left)}`;
};
var lte = (left, right) => {
  return sql`${left} <= ${bindIfParam(right, left)}`;
};
function inArray(column, values) {
  if (Array.isArray(values)) {
    if (values.length === 0)
      return sql`false`;
    return sql`${column} in ${values.map((v) => bindIfParam(v, column))}`;
  }
  return sql`${column} in ${bindIfParam(values, column)}`;
}
function notInArray(column, values) {
  if (Array.isArray(values)) {
    if (values.length === 0)
      return sql`true`;
    return sql`${column} not in ${values.map((v) => bindIfParam(v, column))}`;
  }
  return sql`${column} not in ${bindIfParam(values, column)}`;
}
function isNull(value3) {
  return sql`(${value3} is null)`;
}
function isNotNull(value3) {
  return sql`(${value3} is not null)`;
}
function exists(subquery) {
  return sql`exists ${subquery}`;
}
function notExists(subquery) {
  return sql`not exists ${subquery}`;
}
function between(column, min2, max2) {
  return sql`${column} between ${bindIfParam(min2, column)} and ${bindIfParam(max2, column)}`;
}
function notBetween(column, min2, max2) {
  return sql`${column} not between ${bindIfParam(min2, column)} and ${bindIfParam(max2, column)}`;
}
function like(column, value3) {
  return sql`${column} like ${value3}`;
}
function notLike(column, value3) {
  return sql`${column} not like ${value3}`;
}
function ilike(column, value3) {
  return sql`${column} ilike ${value3}`;
}
function notIlike(column, value3) {
  return sql`${column} not ilike ${value3}`;
}
function arrayContains(column, values) {
  if (Array.isArray(values)) {
    if (values.length === 0)
      throw new Error("arrayContains requires at least one value");
    const par = bindIfParam(values, column);
    return sql`${column} @> ${sql`${Array.isArray(par) ? new Param(par) : par}`}`;
  }
  return sql`${column} @> ${bindIfParam(values, column)}`;
}
function arrayContained(column, values) {
  if (Array.isArray(values)) {
    if (values.length === 0)
      throw new Error("arrayContained requires at least one value");
    const par = bindIfParam(values, column);
    return sql`${column} <@ ${sql`${Array.isArray(par) ? new Param(par) : par}`}`;
  }
  return sql`${column} <@ ${bindIfParam(values, column)}`;
}
function arrayOverlaps(column, values) {
  if (Array.isArray(values)) {
    if (values.length === 0)
      throw new Error("arrayOverlaps requires at least one value");
    const par = bindIfParam(values, column);
    return sql`${column} && ${sql`${Array.isArray(par) ? new Param(par) : par}`}`;
  }
  return sql`${column} && ${bindIfParam(values, column)}`;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sql/expressions/select.js
function asc(column) {
  return sql`${column} asc`;
}
function desc(column) {
  return sql`${column} desc`;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/relations.js
var Relation = class {
  static [entityKind] = "RelationV2";
  fieldName;
  sourceColumns;
  targetColumns;
  alias;
  where;
  sourceTable;
  targetTable;
  through;
  throughTable;
  isReversed;
  sourceColumnTableNames = [];
  targetColumnTableNames = [];
  constructor(targetTable, targetTableName) {
    this.targetTableName = targetTableName;
    this.targetTable = targetTable;
  }
};
var One = class extends Relation {
  static [entityKind] = "OneV2";
  relationType = "one";
  optional;
  constructor(tables, targetTable, targetTableName, config) {
    super(targetTable, targetTableName);
    this.alias = config?.alias;
    this.where = config?.where;
    if (config?.from)
      this.sourceColumns = (Array.isArray(config.from) ? config.from : [config.from]).map((it) => {
        this.throughTable ??= it._.through ? tables[it._.through._.tableName] : undefined;
        this.sourceColumnTableNames.push(it._.tableName);
        return it._.column;
      });
    if (config?.to)
      this.targetColumns = (Array.isArray(config.to) ? config.to : [config.to]).map((it) => {
        this.throughTable ??= it._.through ? tables[it._.through._.tableName] : undefined;
        this.targetColumnTableNames.push(it._.tableName);
        return it._.column;
      });
    if (this.throughTable)
      this.through = {
        source: (Array.isArray(config?.from) ? config.from : (config?.from) ? [config.from] : []).map((c) => c._.through),
        target: (Array.isArray(config?.to) ? config.to : (config?.to) ? [config.to] : []).map((c) => c._.through)
      };
    this.optional = config?.optional ?? true;
  }
};
var operators = {
  and,
  between,
  eq,
  exists,
  gt,
  gte,
  ilike,
  inArray,
  arrayContains,
  arrayContained,
  arrayOverlaps,
  isNull,
  isNotNull,
  like,
  lt,
  lte,
  ne,
  not,
  notBetween,
  notExists,
  notLike,
  notIlike,
  notInArray,
  or,
  sql
};
var orderByOperators = {
  sql,
  asc,
  desc
};
function mapRelationalRow(rows, isOne, buildQueryResultSelection, mapColumnValue, parseJson2 = false, parseJsonIfString = false, useJsonMappers = true) {
  const maxIdx = isOne ? 1 : rows.length;
  const decoders = buildQueryResultSelection.map(({ field, codec, arrayDimensions }) => {
    let decoder;
    if (is2(field, Column)) {
      if (useJsonMappers && field.mapFromJsonValue)
        return (v) => field.mapFromJsonValue(v);
      decoder = field;
    } else if (is2(field, SQL))
      decoder = field.decoder;
    else if (is2(field, SQL.Aliased))
      decoder = field.sql.decoder;
    else if (is2(field, Table) || is2(field, View))
      decoder = noopDecoder;
    else
      decoder = field.getSQL().decoder;
    return decoder.mapFromDriverValue.isNoop ? codec ? (value3) => codec(value3, arrayDimensions) : undefined : codec ? (value3) => decoder.mapFromDriverValue(codec(value3, arrayDimensions)) : (value3) => decoder.mapFromDriverValue(value3);
  });
  for (let i = 0;i < maxIdx; ++i) {
    const row = isOne ? rows : rows[i];
    for (let selectionItemIdx = 0;selectionItemIdx < buildQueryResultSelection.length; ++selectionItemIdx) {
      const selectionItem = buildQueryResultSelection[selectionItemIdx];
      if (selectionItem.selection) {
        if (row[selectionItem.key] === null)
          continue;
        if (parseJson2) {
          row[selectionItem.key] = JSON.parse(row[selectionItem.key]);
          if (row[selectionItem.key] === null)
            continue;
        } else if (parseJsonIfString && typeof row[selectionItem.key] === "string")
          row[selectionItem.key] = JSON.parse(row[selectionItem.key]);
        if (selectionItem.isArray) {
          mapRelationalRow(row[selectionItem.key], false, selectionItem.selection, mapColumnValue, false, parseJsonIfString);
          continue;
        }
        mapRelationalRow(row[selectionItem.key], true, selectionItem.selection, mapColumnValue, false, parseJsonIfString);
        continue;
      }
      if (mapColumnValue)
        row[selectionItem.key] = mapColumnValue(row[selectionItem.key]);
      if (row[selectionItem.key] === null)
        continue;
      const decoder = decoders[selectionItemIdx];
      if (!decoder)
        continue;
      row[selectionItem.key] = decoder(row[selectionItem.key]);
    }
  }
  return rows;
}
function mapRelationalRowFromArrays(rows, isOne, buildQueryResultSelection, mapColumnValue, parseJson2 = false, parseJsonIfString = false) {
  const maxIdx = isOne ? 1 : rows.length;
  const decoders = buildQueryResultSelection.map(({ field, codec, arrayDimensions }) => {
    let decoder;
    if (is2(field, Column))
      decoder = field;
    else if (is2(field, SQL))
      decoder = field.decoder;
    else if (is2(field, SQL.Aliased))
      decoder = field.sql.decoder;
    else if (is2(field, Table) || is2(field, View))
      decoder = noopDecoder;
    else
      decoder = field.getSQL().decoder;
    return decoder.mapFromDriverValue.isNoop ? codec ? (value3) => codec(value3, arrayDimensions) : undefined : codec ? (value3) => decoder.mapFromDriverValue(codec(value3, arrayDimensions)) : (value3) => decoder.mapFromDriverValue(value3);
  });
  const results = Array.from({ length: maxIdx });
  for (let i = 0;i < maxIdx; ++i) {
    const row = isOne ? rows : rows[i];
    const result3 = {};
    for (let selectionItemIdx = 0;selectionItemIdx < buildQueryResultSelection.length; ++selectionItemIdx) {
      const selectionItem = buildQueryResultSelection[selectionItemIdx];
      let value3 = row[selectionItemIdx];
      if (selectionItem.selection) {
        if (value3 === null) {
          result3[selectionItem.key] = null;
          continue;
        }
        if (parseJson2) {
          value3 = JSON.parse(value3);
          if (value3 === null) {
            result3[selectionItem.key] = null;
            continue;
          }
        } else if (parseJsonIfString && typeof value3 === "string")
          value3 = JSON.parse(value3);
        if (selectionItem.isArray)
          mapRelationalRow(value3, false, selectionItem.selection, mapColumnValue, false, parseJsonIfString);
        else
          mapRelationalRow(value3, true, selectionItem.selection, mapColumnValue, false, parseJsonIfString);
        result3[selectionItem.key] = value3;
        continue;
      }
      if (mapColumnValue)
        value3 = mapColumnValue(value3);
      if (value3 === null) {
        result3[selectionItem.key] = null;
        continue;
      }
      const decoder = decoders[selectionItemIdx];
      result3[selectionItem.key] = decoder ? decoder(value3) : value3;
    }
    results[i] = result3;
  }
  return isOne ? results[0] : results;
}
function makeDefaultRqbMapper({ selection, isFirst, parseJson: parseJson2, parseJsonIfString, rootJsonMappers, arrayModeRoot }, mapColumnValue) {
  return (rows) => {
    if (isFirst && !rows[0])
      return rows[0];
    return arrayModeRoot ? mapRelationalRowFromArrays(isFirst ? rows[0] : rows, isFirst, selection, mapColumnValue, parseJson2, parseJsonIfString) : mapRelationalRow(isFirst ? rows[0] : rows, isFirst, selection, mapColumnValue, parseJson2, parseJsonIfString, rootJsonMappers);
  };
}
function makeJitRqbMapperInner(selection, rowExpr, selectionVar, mapColumnValue, parseJson2, parseJsonIfString, useJsonMappers, preFn, counter, accessByIdx) {
  const bodyStmts = [];
  const literalEntries = [];
  let hasWork = false;
  const fieldVars = selection.map(() => `c${counter.n++}`);
  const destructurePieces = selection.map((item, idx) => accessByIdx ? fieldVars[idx] : `${JSON.stringify(item.key)}: ${fieldVars[idx]}`);
  bodyStmts.push(accessByIdx ? `let [ ${destructurePieces.join(", ")} ] = ${rowExpr};` : `let { ${destructurePieces.join(", ")} } = ${rowExpr};`);
  for (const [idx, { field, key, codec, isArray: isArray2, selection: innerSelection, arrayDimensions }] of selection.entries()) {
    const sel = `${selectionVar}[${idx}]`;
    const keyStr = JSON.stringify(key);
    const slot = fieldVars[idx];
    if (innerSelection) {
      if (parseJson2) {
        bodyStmts.push(`if (${slot} !== null) ${slot} = JSON.parse(${slot});`);
        hasWork = true;
      } else if (parseJsonIfString) {
        bodyStmts.push(`if (typeof ${slot} === 'string') ${slot} = JSON.parse(${slot});`);
        hasWork = true;
      }
      const nestedSelVar = `s${counter.n++}`;
      const savedPreFnLen = preFn.length;
      preFn.push(`const { selection: ${nestedSelVar} } = ${sel};`);
      if (isArray2) {
        const j = `j${counter.n++}`;
        const inner = makeJitRqbMapperInner(innerSelection, `${slot}[${j}]`, nestedSelVar, mapColumnValue, false, parseJsonIfString, true, preFn, counter, false);
        if (inner.hasWork) {
          hasWork = true;
          bodyStmts.push(`if (${slot} !== null) {`);
          bodyStmts.push(`	for (let ${j} = 0; ${j} < ${slot}.length; ++${j}) {`);
          for (const s of inner.bodyStmts)
            bodyStmts.push(`		${s}`);
          bodyStmts.push(`		${slot}[${j}] = ${inner.literal};`);
          bodyStmts.push(`	}`);
          bodyStmts.push(`}`);
        } else
          preFn.splice(savedPreFnLen, 1);
      } else {
        const inner = makeJitRqbMapperInner(innerSelection, slot, nestedSelVar, mapColumnValue, false, parseJsonIfString, true, preFn, counter, false);
        if (inner.hasWork) {
          hasWork = true;
          bodyStmts.push(`if (${slot} !== null) {`);
          for (const s of inner.bodyStmts)
            bodyStmts.push(`	${s}`);
          bodyStmts.push(`	${slot} = ${inner.literal};`);
          bodyStmts.push(`}`);
        } else
          preFn.splice(savedPreFnLen, 1);
      }
      literalEntries.push(`${keyStr}: ${slot}`);
      continue;
    }
    let decoderExpr = "";
    let destructure = "";
    let bypassCodecs = false;
    if (is2(field, Column)) {
      if (useJsonMappers && field.mapFromJsonValue) {
        bypassCodecs = true;
        const id = counter.n++;
        destructure = `field: dec${id}`;
        decoderExpr = `dec${id}.mapFromJsonValue`;
      } else if (!field.mapFromDriverValue.isNoop) {
        const id = counter.n++;
        destructure = `field: dec${id}`;
        decoderExpr = `dec${id}.mapFromDriverValue`;
      }
    } else if (is2(field, SQL)) {
      if (!field.decoder.mapFromDriverValue.isNoop) {
        const id = counter.n++;
        destructure = `field: { decoder: dec${id} }`;
        decoderExpr = `dec${id}.mapFromDriverValue`;
      }
    } else if (is2(field, SQL.Aliased)) {
      if (!field.sql.decoder.mapFromDriverValue.isNoop) {
        const id = counter.n++;
        destructure = `field: { sql: { decoder: dec${id} } }`;
        decoderExpr = `dec${id}.mapFromDriverValue`;
      }
    } else if (is2(field, Table) || is2(field, View)) {} else if (!field.getSQL().decoder.mapFromDriverValue.isNoop) {
      const id = counter.n++;
      preFn.push(`const dec${id} = ${sel}.field.getSQL().decoder;`);
      decoderExpr = `dec${id}.mapFromDriverValue`;
    }
    let codecVar = "";
    if (!bypassCodecs && codec)
      codecVar = `codec${counter.n++}`;
    if (destructure || codecVar) {
      const parts = [];
      if (destructure)
        parts.push(destructure);
      if (codecVar)
        parts.push(`codec: ${codecVar}`);
      preFn.push(`const { ${parts.join(", ")} } = ${sel};`);
    }
    if (mapColumnValue) {
      hasWork = true;
      bodyStmts.push(`${slot} = mapColumnValue(${slot});`);
      if (decoderExpr || codecVar) {
        let decoded = slot;
        if (codecVar)
          decoded = `${codecVar}(${decoded}, ${arrayDimensions})`;
        if (decoderExpr)
          decoded = `${decoderExpr}(${decoded})`;
        bodyStmts.push(`if (${slot} !== null) ${slot} = ${decoded};`);
      }
      literalEntries.push(`${keyStr}: ${slot}`);
    } else if (decoderExpr || codecVar) {
      hasWork = true;
      let decoded = slot;
      if (codecVar)
        decoded = `${codecVar}(${decoded}, ${arrayDimensions})`;
      if (decoderExpr)
        decoded = `${decoderExpr}(${decoded})`;
      literalEntries.push(`${keyStr}: ${slot} === null ? null : ${decoded}`);
    } else
      literalEntries.push(`${keyStr}: ${slot}`);
  }
  return {
    bodyStmts,
    literal: `{ ${literalEntries.join(", ")} }`,
    hasWork
  };
}
function makeJitRqbMapper({ selection, isFirst, parseJson: parseJson2, parseJsonIfString, rootJsonMappers, arrayModeRoot }, mapColumnValue) {
  const preFn = [];
  const inner = makeJitRqbMapperInner(selection, "row", "selection", mapColumnValue, parseJson2, parseJsonIfString, arrayModeRoot ? false : rootJsonMappers, preFn, { n: 0 }, !!arrayModeRoot);
  const lines = [];
  lines.push(`	"use strict";
	const { selection${mapColumnValue ? `, mapColumnValue` : ""} } = this;`);
  for (const p of preFn)
    lines.push(`	${p}`);
  if (arrayModeRoot)
    if (isFirst) {
      lines.push(`	const row = rows[0];`);
      lines.push(`	if (!row) return undefined;`);
      for (const s of inner.bodyStmts)
        lines.push(`	${s}`);
      lines.push(`	return ${inner.literal};`);
    } else {
      lines.push(`	const { length } = rows;`);
      lines.push(`	const mapped = Array.from({ length });`);
      lines.push(`	for (let i = 0; i < length; ++i) {`);
      lines.push(`		const row = rows[i];`);
      for (const s of inner.bodyStmts)
        lines.push(`		${s}`);
      lines.push(`		mapped[i] = ${inner.literal};`);
      lines.push(`	}`);
      lines.push(`	return mapped;`);
    }
  else if (!inner.hasWork)
    lines.push(isFirst ? `	return rows[0];` : `	return rows;`);
  else if (isFirst) {
    lines.push(`	const row = rows[0];`);
    lines.push(`	if (!row) return undefined;`);
    for (const s of inner.bodyStmts)
      lines.push(`	${s}`);
    lines.push(`	rows[0] = ${inner.literal};`);
    lines.push(`	return rows[0];`);
  } else {
    lines.push(`	for (let i = 0; i < rows.length; ++i) {`);
    lines.push(`		const row = rows[i];`);
    for (const s of inner.bodyStmts)
      lines.push(`		${s}`);
    lines.push(`		rows[i] = ${inner.literal};`);
    lines.push(`	}`);
    lines.push(`	return rows;`);
  }
  lines.push("\t//# sourceURL=drizzle:jit-relational-query-mapper");
  const compiled = lines.join(`
`);
  return Object.assign(new FnConstructor("rows", compiled).bind({
    selection,
    mapColumnValue
  }), { body: `function jitRqbMapper (rows) {
${compiled}
}` });
}
function fieldSelectionToSQL(table, target) {
  const field = table[TableColumns][target];
  return field ? is2(field, Column) ? field : is2(field, SQL.Aliased) ? sql`${table}.${sql.identifier(field.fieldAlias)}` : sql`${table}.${sql.identifier(target)}` : sql`${table}.${sql.identifier(target)}`;
}
function relationsFieldFilterToSQL(column, filter6) {
  if (typeof filter6 !== "object" || is2(filter6, Placeholder))
    return eq(column, filter6);
  const entries = Object.entries(filter6);
  if (!entries.length)
    return;
  const parts = [];
  for (const [target, value3] of entries) {
    if (value3 === undefined)
      continue;
    switch (target) {
      case "NOT": {
        const res = relationsFieldFilterToSQL(column, value3);
        if (!res)
          continue;
        parts.push(not(res));
        continue;
      }
      case "OR":
        if (!value3.length)
          continue;
        parts.push(or(...value3.map((subFilter) => relationsFieldFilterToSQL(column, subFilter))));
        continue;
      case "AND":
        if (!value3.length)
          continue;
        parts.push(and(...value3.map((subFilter) => relationsFieldFilterToSQL(column, subFilter))));
        continue;
      case "isNotNull":
      case "isNull":
        if (!value3)
          continue;
        parts.push(operators[target](column));
        continue;
      case "in":
        parts.push(operators.inArray(column, value3));
        continue;
      case "notIn":
        parts.push(operators.notInArray(column, value3));
        continue;
      default:
        parts.push(operators[target](column, value3));
        continue;
    }
  }
  if (!parts.length)
    return;
  return and(...parts);
}
function relationsFilterToSQL(table, filter6, tableRelations = {}, tablesRelations = {}, depth = 0) {
  const entries = Object.entries(filter6);
  if (!entries.length)
    return;
  const parts = [];
  for (const [target, value3] of entries) {
    if (value3 === undefined)
      continue;
    switch (target) {
      case "RAW": {
        const processed = typeof value3 === "function" ? value3(table, operators) : value3.getSQL();
        parts.push(processed);
        continue;
      }
      case "OR":
        if (!value3?.length)
          continue;
        parts.push(or(...value3.map((subFilter) => relationsFilterToSQL(table, subFilter, tableRelations, tablesRelations, depth))));
        continue;
      case "AND":
        if (!value3?.length)
          continue;
        parts.push(and(...value3.map((subFilter) => relationsFilterToSQL(table, subFilter, tableRelations, tablesRelations, depth))));
        continue;
      case "NOT": {
        if (value3 === undefined)
          continue;
        const built = relationsFilterToSQL(table, value3, tableRelations, tablesRelations, depth);
        if (!built)
          continue;
        parts.push(not(built));
        continue;
      }
      default: {
        if (table[TableColumns][target]) {
          const colFilter = relationsFieldFilterToSQL(fieldSelectionToSQL(table, target), value3);
          if (colFilter)
            parts.push(colFilter);
          continue;
        }
        const relation = tableRelations[target];
        if (!relation)
          throw new DrizzleError({ message: `Unknown relational filter field: "${target}"` });
        const targetTable = aliasedTable(relation.targetTable, `f${depth}`);
        const throughTable = relation.throughTable ? aliasedTable(relation.throughTable, `ft${depth}`) : undefined;
        const targetConfig = tablesRelations[relation.targetTableName];
        const { filter: relationFilter, joinCondition } = relationToSQL(relation, table, targetTable, throughTable);
        const filter7 = and(relationFilter, typeof value3 === "boolean" ? undefined : relationsFilterToSQL(targetTable, value3, targetConfig.relations, tablesRelations, depth + 1));
        const subquery = throughTable ? sql`(select * from ${getTableAsAliasSQL(targetTable)} inner join ${getTableAsAliasSQL(throughTable)} on ${joinCondition}${sql` where ${filter7}`.if(filter7)} limit 1)` : sql`(select * from ${getTableAsAliasSQL(targetTable)}${sql` where ${filter7}`.if(filter7)} limit 1)`;
        if (filter7)
          parts.push((value3 ? exists : notExists)(subquery));
      }
    }
  }
  return and(...parts);
}
function relationsOrderToSQL(table, orders) {
  if (typeof orders === "function") {
    const data = orders(table, orderByOperators);
    return is2(data, SQL) ? data : Array.isArray(data) ? data.length ? sql.join(data.map((o) => is2(o, SQL) ? o : asc(o)), sql`, `) : undefined : is2(data, Column) ? asc(data) : undefined;
  }
  const entries = Object.entries(orders).filter(([_, value3]) => value3);
  if (!entries.length)
    return;
  return sql.join(entries.map(([target, value3]) => (value3 === "asc" ? asc : desc)(fieldSelectionToSQL(table, target))), sql`, `);
}
function relationExtrasToSQL(table, extras) {
  const subqueries = [];
  const selection = [];
  for (const [key, field] of Object.entries(extras)) {
    if (!field)
      continue;
    const extra = typeof field === "function" ? field(table, { sql: operators.sql }) : field;
    const query = sql`(${extra.getSQL()}) as ${sql.identifier(key)}`;
    query.decoder = extra.getSQL().decoder;
    subqueries.push(query);
    selection.push({
      key,
      field: query
    });
  }
  return {
    sql: subqueries.length ? sql.join(subqueries, sql`, `) : undefined,
    selection
  };
}
function relationToSQL(relation, sourceTable, targetTable, throughTable) {
  if (relation.through) {
    const outerColumnWhere = relation.sourceColumns.map((s, i) => {
      const t = relation.through.source[i];
      return eq(sql`${sourceTable}.${sql.identifier(s.name)}`, sql`${throughTable}.${sql.identifier(is2(t._.column, Column) ? t._.column.name : t._.key)}`);
    });
    const innerColumnWhere = relation.targetColumns.map((s, i) => {
      const t = relation.through.target[i];
      return eq(sql`${throughTable}.${sql.identifier(is2(t._.column, Column) ? t._.column.name : t._.key)}`, sql`${targetTable}.${sql.identifier(s.name)}`);
    });
    return {
      filter: and(relation.where ? relationsFilterToSQL(relation.isReversed ? sourceTable : targetTable, relation.where) : undefined, ...outerColumnWhere),
      joinCondition: and(...innerColumnWhere)
    };
  }
  return { filter: and(...relation.sourceColumns.map((s, i) => {
    const t = relation.targetColumns[i];
    return eq(sql`${sourceTable}.${sql.identifier(s.name)}`, sql`${targetTable}.${sql.identifier(t.name)}`);
  }), relation.where ? relationsFilterToSQL(relation.isReversed ? sourceTable : targetTable, relation.where) : undefined) };
}
function getTableAsAliasSQL(table) {
  return sql`${table[IsAlias] ? sql`${sql`${sql.identifier(table[TableSchema] ?? "")}.`.if(table[TableSchema])}${sql.identifier(table[OriginalName])} as ${table}` : table}`;
}
// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/foreign-keys.js
var ForeignKeyBuilder = class {
  static [entityKind] = "PgForeignKeyBuilder";
  reference;
  _onUpdate = "no action";
  _onDelete = "no action";
  constructor(config, actions) {
    this.reference = () => {
      const { name, columns, foreignColumns } = config();
      return {
        name,
        columns,
        foreignTable: foreignColumns[0].table,
        foreignColumns
      };
    };
    if (actions) {
      this._onUpdate = actions.onUpdate;
      this._onDelete = actions.onDelete;
    }
  }
  onUpdate(action) {
    this._onUpdate = action === undefined ? "no action" : action;
    return this;
  }
  onDelete(action) {
    this._onDelete = action === undefined ? "no action" : action;
    return this;
  }
  build(table) {
    return new ForeignKey(table, this);
  }
};
var ForeignKey = class {
  static [entityKind] = "PgForeignKey";
  reference;
  onUpdate;
  onDelete;
  name;
  constructor(table, builder) {
    this.table = table;
    this.reference = builder.reference;
    this.onUpdate = builder._onUpdate;
    this.onDelete = builder._onDelete;
  }
  getName() {
    const { name, columns, foreignColumns } = this.reference();
    const columnNames = columns.map((column) => column.name);
    const foreignColumnNames = foreignColumns.map((column) => column.name);
    const chunks = [
      this.table[TableName],
      ...columnNames,
      foreignColumns[0].table[TableName],
      ...foreignColumnNames
    ];
    return name ?? `${chunks.join("_")}_fk`;
  }
  isNameExplicit() {
    return !!this.reference().name;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/common.js
var PgColumnBuilder = class {
  static [entityKind] = "PgColumnBuilder";
  foreignKeyConfigs = [];
  config;
  constructor(name, dataType, columnType) {
    this.config = {
      name,
      keyAsName: name === "",
      notNull: false,
      default: undefined,
      hasDefault: false,
      primaryKey: false,
      isUnique: false,
      uniqueName: undefined,
      uniqueType: undefined,
      dataType,
      columnType,
      generated: undefined,
      defaultFn: undefined,
      onUpdateFn: undefined,
      generatedIdentity: undefined
    };
  }
  $type() {
    return this;
  }
  notNull() {
    this.config.notNull = true;
    return this;
  }
  default(value3) {
    this.config.default = value3;
    this.config.hasDefault = true;
    return this;
  }
  $defaultFn(fn3) {
    this.config.defaultFn = fn3;
    this.config.hasDefault = true;
    return this;
  }
  $default = this.$defaultFn;
  $onUpdateFn(fn3) {
    this.config.onUpdateFn = fn3;
    this.config.hasDefault = true;
    return this;
  }
  $onUpdate = this.$onUpdateFn;
  primaryKey() {
    this.config.primaryKey = true;
    this.config.notNull = true;
    return this;
  }
  setName(name, casingFn) {
    if (this.config.name !== "")
      return;
    this.config.name = casingFn(name);
  }
  array(dimensions) {
    const dim = dimensions ?? "[]";
    this.config.dimensions = dim.length / 2;
    return this;
  }
  references(ref, config = {}) {
    this.foreignKeyConfigs.push({
      ref,
      config
    });
    return this;
  }
  unique(name, config) {
    this.config.isUnique = true;
    this.config.uniqueName = name;
    this.config.uniqueType = config?.nulls;
    return this;
  }
  generatedAlwaysAs(as3) {
    this.config.generated = {
      as: as3,
      type: "always",
      mode: "stored"
    };
    return this;
  }
  buildForeignKeys(column, table) {
    return this.foreignKeyConfigs.map(({ ref, config }) => {
      return iife((ref2, config2) => {
        const builder = new ForeignKeyBuilder(() => {
          const foreignColumn = ref2();
          return {
            name: config2.name,
            columns: [column],
            foreignColumns: [foreignColumn]
          };
        });
        if (config2.onUpdate)
          builder.onUpdate(config2.onUpdate);
        if (config2.onDelete)
          builder.onDelete(config2.onDelete);
        return builder.build(table);
      }, ref, config);
    });
  }
  buildExtraConfigColumn(table) {
    return new ExtraConfigColumn(table, {
      ...this.config,
      dimensions: this.config.dimensions ?? 0
    });
  }
};
var PgColumn = class extends Column {
  static [entityKind] = "PgColumn";
  table;
  dimensions;
  constructor(table, config) {
    super(table, config);
    this.table = table;
    this.dimensions = config.dimensions ?? 0;
  }
  postBuild() {
    if (this.dimensions) {
      const originalFromDriver = this.mapFromDriverValue.bind(this);
      const originalToDriver = this.mapToDriverValue.bind(this);
      this.mapFromDriverValue = this.mapFromDriverValue.isNoop ? this.mapFromDriverValue : (value3) => {
        return this.mapArrayElements(value3, originalFromDriver, this.dimensions);
      };
      this.mapToDriverValue = this.mapToDriverValue.isNoop ? this.mapToDriverValue : (value3) => {
        return this.mapArrayElements(value3, originalToDriver, this.dimensions);
      };
    }
    return this;
  }
  mapArrayElements(value3, mapper, depth) {
    if (depth > 0 && Array.isArray(value3))
      return value3.map((v) => v === null ? null : this.mapArrayElements(v, mapper, depth - 1));
    return mapper(value3);
  }
};
var ExtraConfigColumn = class extends PgColumn {
  static [entityKind] = "ExtraConfigColumn";
  codec = undefined;
  getSQLType() {
    return this.getSQLType();
  }
  indexConfig = {
    order: this.config.order ?? "asc",
    nulls: this.config.nulls ?? "last",
    opClass: this.config.opClass
  };
  defaultConfig = {
    order: "asc",
    nulls: "last",
    opClass: undefined
  };
  asc() {
    this.indexConfig.order = "asc";
    return this;
  }
  desc() {
    this.indexConfig.order = "desc";
    return this;
  }
  nullsFirst() {
    this.indexConfig.nulls = "first";
    return this;
  }
  nullsLast() {
    this.indexConfig.nulls = "last";
    return this;
  }
  op(opClass) {
    this.indexConfig.opClass = opClass;
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/int.common.js
var PgIntColumnBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgIntColumnBaseBuilder";
  generatedAlwaysAsIdentity(sequence) {
    if (sequence) {
      const { name, ...options } = sequence;
      this.config.generatedIdentity = {
        type: "always",
        sequenceName: name,
        sequenceOptions: options
      };
    } else
      this.config.generatedIdentity = { type: "always" };
    this.config.hasDefault = true;
    this.config.notNull = true;
    return this;
  }
  generatedByDefaultAsIdentity(sequence) {
    if (sequence) {
      const { name, ...options } = sequence;
      this.config.generatedIdentity = {
        type: "byDefault",
        sequenceName: name,
        sequenceOptions: options
      };
    } else
      this.config.generatedIdentity = { type: "byDefault" };
    this.config.hasDefault = true;
    this.config.notNull = true;
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/bigint.js
var PgBigInt53Builder = class extends PgIntColumnBuilder {
  static [entityKind] = "PgBigInt53Builder";
  constructor(name) {
    super(name, "number int53", "PgBigInt53");
  }
  build(table) {
    return new PgBigInt53(table, this.config);
  }
};
var PgBigInt53 = class extends PgColumn {
  static [entityKind] = "PgBigInt53";
  codec = "bigint:number";
  getSQLType() {
    return "bigint";
  }
};
var PgBigInt64Builder = class extends PgIntColumnBuilder {
  static [entityKind] = "PgBigInt64Builder";
  constructor(name) {
    super(name, "bigint int64", "PgBigInt64");
  }
  build(table) {
    return new PgBigInt64(table, this.config);
  }
};
var PgBigInt64 = class extends PgColumn {
  static [entityKind] = "PgBigInt64";
  codec = "bigint";
  getSQLType() {
    return "bigint";
  }
};
var PgBigIntStringBuilder = class extends PgIntColumnBuilder {
  static [entityKind] = "PgBigIntStringBuilder";
  constructor(name) {
    super(name, "string int64", "PgBigIntString");
  }
  build(table) {
    return new PgBigIntString(table, this.config);
  }
};
var PgBigIntString = class extends PgColumn {
  static [entityKind] = "PgBigIntString";
  codec = "bigint:string";
  getSQLType() {
    return "bigint";
  }
};
function bigint(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (config.mode === "number")
    return new PgBigInt53Builder(name);
  if (config.mode === "string")
    return new PgBigIntStringBuilder(name);
  return new PgBigInt64Builder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/bigserial.js
var PgBigSerial53Builder = class extends PgColumnBuilder {
  static [entityKind] = "PgBigSerial53Builder";
  constructor(name) {
    super(name, "number int53", "PgBigSerial53");
    this.config.hasDefault = true;
    this.config.notNull = true;
  }
  build(table) {
    return new PgBigSerial53(table, this.config);
  }
};
var PgBigSerial53 = class extends PgColumn {
  static [entityKind] = "PgBigSerial53";
  codec = "bigserial:number";
  getSQLType() {
    return "bigserial";
  }
};
var PgBigSerial64Builder = class extends PgColumnBuilder {
  static [entityKind] = "PgBigSerial64Builder";
  constructor(name) {
    super(name, "bigint int64", "PgBigSerial64");
    this.config.hasDefault = true;
    this.config.notNull = true;
  }
  build(table) {
    return new PgBigSerial64(table, this.config);
  }
};
var PgBigSerial64 = class extends PgColumn {
  static [entityKind] = "PgBigSerial64";
  codec = "bigserial";
  getSQLType() {
    return "bigserial";
  }
};
function bigserial(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (config.mode === "number")
    return new PgBigSerial53Builder(name);
  return new PgBigSerial64Builder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/boolean.js
var PgBooleanBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgBooleanBuilder";
  constructor(name) {
    super(name, "boolean", "PgBoolean");
  }
  build(table) {
    return new PgBoolean(table, this.config);
  }
};
var PgBoolean = class extends PgColumn {
  static [entityKind] = "PgBoolean";
  codec = "bool";
  getSQLType() {
    return "boolean";
  }
};
function boolean2(name) {
  return new PgBooleanBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/char.js
var PgCharBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgCharBuilder";
  constructor(name, config) {
    super(name, config.enum?.length ? "string enum" : "string", "PgChar");
    this.config.length = config.length ?? 1;
    this.config.setLength = config.length !== undefined;
    this.config.enumValues = config.enum;
  }
  build(table) {
    return new PgChar(table, this.config);
  }
};
var PgChar = class extends PgColumn {
  static [entityKind] = "PgChar";
  codec = "char";
  enumValues;
  setLength;
  constructor(table, config) {
    super(table, config);
    this.enumValues = config.enumValues;
    this.setLength = config.setLength;
  }
  getSQLType() {
    return this.setLength ? `char(${this.length})` : `char`;
  }
};
function char(a, b = {}) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgCharBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/cidr.js
var PgCidrBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgCidrBuilder";
  constructor(name) {
    super(name, "string cidr", "PgCidr");
  }
  build(table) {
    return new PgCidr(table, this.config);
  }
};
var PgCidr = class extends PgColumn {
  static [entityKind] = "PgCidr";
  codec = "cidr";
  getSQLType() {
    return "cidr";
  }
};
function cidr(name) {
  return new PgCidrBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/array.js
function parsePgArrayValue(arrayString, startFrom, inQuotes) {
  for (let i = startFrom;i < arrayString.length; i++) {
    const char2 = arrayString[i];
    if (char2 === "\\") {
      i++;
      continue;
    }
    if (char2 === '"')
      return [arrayString.slice(startFrom, i).replace(/\\/g, ""), i + 1];
    if (inQuotes)
      continue;
    if (char2 === "," || char2 === "}")
      return [arrayString.slice(startFrom, i).replace(/\\/g, ""), i];
  }
  return [arrayString.slice(startFrom).replace(/\\/g, ""), arrayString.length];
}
function parsePgNestedArray(arrayString, startFrom = 0) {
  const result3 = [];
  let i = startFrom;
  let lastCharIsComma = false;
  while (i < arrayString.length) {
    const char2 = arrayString[i];
    if (char2 === ",") {
      if (lastCharIsComma || i === startFrom)
        result3.push("");
      lastCharIsComma = true;
      i++;
      continue;
    }
    lastCharIsComma = false;
    if (char2 === "\\") {
      i += 2;
      continue;
    }
    if (char2 === '"') {
      const [value4, startFrom2] = parsePgArrayValue(arrayString, i + 1, true);
      result3.push(value4);
      i = startFrom2;
      continue;
    }
    if (char2 === "}")
      return [result3, i + 1];
    if (char2 === "{") {
      const [value4, startFrom2] = parsePgNestedArray(arrayString, i + 1);
      result3.push(value4);
      i = startFrom2;
      continue;
    }
    const [value3, newStartFrom] = parsePgArrayValue(arrayString, i, false);
    result3.push(value3);
    i = newStartFrom;
  }
  return [result3, i];
}
function parsePgArray(arrayString) {
  const [result3] = parsePgNestedArray(arrayString, 1);
  return result3;
}
function makePgArray(array2) {
  return `{${array2.map((item) => {
    if (Array.isArray(item))
      return makePgArray(item);
    if (typeof item === "string")
      return `"${item.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
    return `${item}`;
  }).join(",")}}`;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/postgis_extension/utils.js
function hexToBytes(hex) {
  const bytes = [];
  for (let c = 0;c < hex.length; c += 2)
    bytes.push(Number.parseInt(hex.slice(c, c + 2), 16));
  return new Uint8Array(bytes);
}
function bytesToFloat64(bytes, offset) {
  const buffer = /* @__PURE__ */ new ArrayBuffer(8);
  const view = new DataView(buffer);
  for (let i = 0;i < 8; i++)
    view.setUint8(i, bytes[offset + i]);
  return view.getFloat64(0, true);
}
function parseEWKB(hex) {
  const bytes = hexToBytes(hex);
  let offset = 0;
  const byteOrder = bytes[offset];
  offset += 1;
  const view = new DataView(bytes.buffer);
  const geomType = view.getUint32(offset, byteOrder === 1);
  offset += 4;
  let srid;
  if (geomType & 536870912) {
    srid = view.getUint32(offset, byteOrder === 1);
    offset += 4;
  }
  if ((geomType & 65535) === 1) {
    const x = bytesToFloat64(bytes, offset);
    offset += 8;
    const y = bytesToFloat64(bytes, offset);
    offset += 8;
    return {
      srid,
      point: [x, y]
    };
  }
  throw new Error("Unsupported geometry type");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/codecs.js
var PG_ALIAS_TO_TYPE_MAP = {
  int2: "smallint",
  integer: "int",
  int4: "int",
  int8: "bigint",
  decimal: "numeric",
  real: "float4",
  double: "float8",
  "double precision": "float8",
  serial2: "smallserial",
  serial4: "serial",
  serial8: "bigserial",
  character: "char",
  "character varying": "varchar",
  "time with time zone": "timetz",
  "timestamp with time zone": "timestamptz",
  boolean: "bool",
  "bit varying": "varbit"
};
function resolvePgType(type) {
  return PG_ALIAS_TO_TYPE_MAP[type] ?? type;
}
var castToText = (name) => sql`${name}::text`;
var castToTextArr = (name, arrayDimensions) => sql`${name}::text${sql.raw("[]".repeat(arrayDimensions))}`;
var arrayCompatCast = (cast) => (name, arrayDimensions) => {
  if (!arrayDimensions)
    return cast(name);
  const aliases = [];
  for (let i = 0;i < arrayDimensions; i++)
    aliases.push(sql.identifier(`s${i}`));
  let indexed = name;
  for (const alias of aliases)
    indexed = sql`${indexed}[${alias}]`;
  let expression = sql`array(\
select ${cast(indexed)} \
from generate_subscripts(${name}, ${sql.raw(arrayDimensions.toString())}) ${aliases[arrayDimensions - 1]} \
order by ${aliases[arrayDimensions - 1]})`;
  for (let dim = arrayDimensions - 1;dim > 0; dim--)
    expression = sql`array(\
select ${expression} \
from generate_subscripts(${name}, ${sql.raw(dim.toString())}) ${aliases[dim - 1]} \
order by ${aliases[dim - 1]})`;
  return sql`case when ${name} is null then null else ${expression} end`;
};
var arrayCompatNormalize = (normalize) => {
  const loop = (value3, arrayDimensions) => {
    const innerDimensions = arrayDimensions - 1;
    if (arrayDimensions > 1)
      for (let i = 0;i < value3.length; ++i)
        loop(value3[i], innerDimensions);
    else
      for (let i = 0;i < value3.length; ++i)
        value3[i] = normalize(value3[i]);
    return value3;
  };
  return loop;
};
var arrayCompatNormalizeInput = (normalize, transformToPgArray = false) => {
  const loop = (value3, arrayDimensions) => {
    const innerDimensions = arrayDimensions - 1;
    const out = Array.from({ length: value3.length });
    if (arrayDimensions > 1)
      for (let i = 0;i < value3.length; ++i)
        out[i] = loop(value3[i], innerDimensions);
    else
      for (let i = 0;i < value3.length; ++i)
        out[i] = normalize(value3[i]);
    return out;
  };
  return transformToPgArray ? (v, d) => makePgArray(loop(v, d)) : loop;
};
var parsePgArrayAndNormalize = (normalize) => {
  const codec = arrayCompatNormalize(normalize);
  return (value3, arrayDimensions) => codec(parsePgArray(value3), arrayDimensions);
};
var parseLineTuple = (v) => {
  const [a, b, c] = v.slice(1, -1).split(",");
  return [
    Number.parseFloat(a),
    Number.parseFloat(b),
    Number.parseFloat(c)
  ];
};
var parseLineABC = (v) => {
  const [a, b, c] = v.slice(1, -1).split(",");
  return {
    a: Number.parseFloat(a),
    b: Number.parseFloat(b),
    c: Number.parseFloat(c)
  };
};
var parsePointTuple = (v) => {
  const [x, y] = v.slice(1, -1).split(",");
  return [Number.parseFloat(x), Number.parseFloat(y)];
};
var parsePointXY = (v) => {
  const [x, y] = v.slice(1, -1).split(",");
  return {
    x: Number.parseFloat(x),
    y: Number.parseFloat(y)
  };
};
var parseGeometryTuple = (v) => parseEWKB(v).point;
var parseGeometryXY = (v) => {
  const parsed = parseEWKB(v);
  return {
    x: parsed.point[0],
    y: parsed.point[1]
  };
};
var textToDate = (v) => new Date(v);
var textToDateWithTz = (v) => /* @__PURE__ */ new Date(v + "+0000");
var parsePgVector = (v) => {
  const body = v.slice(1, -1);
  if (body.length === 0)
    return [];
  return body.split(",").map(Number.parseFloat);
};
var genericPgCodecs = {
  bytea: {
    castInJson: (name) => sql`encode(${name}, 'base64')`,
    castArrayInJson: arrayCompatCast((name) => sql`encode(${name}, 'base64')`),
    normalizeInJson: (v) => Buffer.from(v, "base64"),
    normalizeArrayInJson: arrayCompatNormalize((v) => Buffer.from(v, "base64"))
  },
  bigint: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalizeInJson: BigInt,
    normalizeArrayInJson: arrayCompatNormalize(BigInt)
  },
  "bigint:number": {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: Number,
    normalizeArray: arrayCompatNormalize(Number),
    normalizeInJson: Number,
    normalizeArrayInJson: arrayCompatNormalize(Number)
  },
  "bigint:string": {
    castInJson: castToText,
    castArrayInJson: castToTextArr
  },
  bigserial: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalizeInJson: BigInt,
    normalizeArrayInJson: arrayCompatNormalize(BigInt),
    normalize: BigInt,
    normalizeArray: arrayCompatNormalize(BigInt)
  },
  "bigserial:number": {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: Number,
    normalizeArray: arrayCompatNormalize(Number),
    normalizeInJson: Number,
    normalizeArrayInJson: arrayCompatNormalize(Number)
  },
  date: {
    normalizeInJson: textToDate,
    normalizeArrayInJson: arrayCompatNormalize(textToDate)
  },
  "date:string": {},
  enum: {
    castArray: castToTextArr,
    normalizeParamArray: makePgArray
  },
  geometry: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: parseGeometryXY,
    normalizeArray: arrayCompatNormalize(parseGeometryXY),
    normalizeInJson: parseGeometryXY,
    normalizeArrayInJson: arrayCompatNormalize(parseGeometryXY)
  },
  "geometry:tuple": {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: parseGeometryTuple,
    normalizeArray: arrayCompatNormalize(parseGeometryTuple),
    normalizeInJson: parseGeometryTuple,
    normalizeArrayInJson: arrayCompatNormalize(parseGeometryTuple)
  },
  interval: { castArrayInJson: castToTextArr },
  json: { normalizeParamArray: arrayCompatNormalizeInput((v) => JSON.stringify(v), true) },
  jsonb: { normalizeParamArray: arrayCompatNormalizeInput((v) => JSON.stringify(v), true) },
  line: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: parseLineABC,
    normalizeArray: arrayCompatNormalize(parseLineABC),
    normalizeInJson: parseLineABC,
    normalizeArrayInJson: arrayCompatNormalize(parseLineABC)
  },
  "line:tuple": {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: parseLineTuple,
    normalizeArray: arrayCompatNormalize(parseLineTuple),
    normalizeInJson: parseLineTuple,
    normalizeArrayInJson: arrayCompatNormalize(parseLineTuple)
  },
  numeric: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    castArray: castToTextArr
  },
  "numeric:number": {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    castArray: castToTextArr,
    normalize: Number,
    normalizeArray: arrayCompatNormalize(Number),
    normalizeInJson: Number,
    normalizeArrayInJson: arrayCompatNormalize(Number)
  },
  "numeric:bigint": {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    castArray: castToTextArr,
    normalize: BigInt,
    normalizeArray: arrayCompatNormalize(BigInt),
    normalizeInJson: BigInt,
    normalizeArrayInJson: arrayCompatNormalize(BigInt)
  },
  point: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: parsePointXY,
    normalizeArray: arrayCompatNormalize(parsePointXY),
    normalizeInJson: parsePointXY,
    normalizeArrayInJson: arrayCompatNormalize(parsePointXY)
  },
  "point:tuple": {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalize: parsePointTuple,
    normalizeArray: arrayCompatNormalize(parsePointTuple),
    normalizeInJson: parsePointTuple,
    normalizeArrayInJson: arrayCompatNormalize(parsePointTuple)
  },
  timestamp: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalizeInJson: textToDateWithTz,
    normalizeArrayInJson: arrayCompatNormalize(textToDateWithTz)
  },
  timestamptz: {
    castInJson: castToText,
    castArrayInJson: castToTextArr,
    normalizeInJson: textToDate,
    normalizeArrayInJson: arrayCompatNormalize(textToDate)
  },
  "timestamp:string": {
    castInJson: castToText,
    castArrayInJson: castToTextArr
  },
  "timestamptz:string": {
    castInJson: castToText,
    castArrayInJson: castToTextArr
  },
  halfvec: {
    normalize: parsePgVector,
    normalizeArray: parsePgArrayAndNormalize(parsePgVector),
    normalizeInJson: parsePgVector,
    normalizeArrayInJson: arrayCompatNormalize(parsePgVector)
  },
  vector: {
    normalize: parsePgVector,
    normalizeArray: parsePgArrayAndNormalize(parsePgVector),
    normalizeInJson: parsePgVector,
    normalizeArrayInJson: arrayCompatNormalize(parsePgVector)
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/custom.js
var PgCustomColumnBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgCustomColumnBuilder";
  constructor(name, fieldConfig, customTypeParams) {
    super(name, "custom", "PgCustomColumn");
    this.config.fieldConfig = fieldConfig;
    this.config.customTypeParams = customTypeParams;
  }
  build(table) {
    return new PgCustomColumn(table, this.config);
  }
};
var PgCustomColumn = class extends PgColumn {
  static [entityKind] = "PgCustomColumn";
  codec;
  sqlName;
  mapFromJsonValue;
  jsonSelectIdentifier;
  constructor(table, config) {
    super(table, config);
    this.sqlName = config.customTypeParams.dataType(config.fieldConfig);
    this.mapToDriverValue = config.customTypeParams.toDriver ?? this.mapToDriverValue;
    this.mapFromDriverValue = config.customTypeParams.fromDriver ?? this.mapFromDriverValue;
    this.mapFromJsonValue = config.customTypeParams.fromJson;
    this.jsonSelectIdentifier = config.customTypeParams.forJsonSelect;
    this.codec = resolvePgType(config.customTypeParams.codec ?? this.sqlName.slice(0, Math.min(...[this.sqlName.indexOf("("), this.sqlName.indexOf("[")].filter((e) => e !== -1))));
    if (this.dimensions && config.customTypeParams.fromJson)
      this.mapFromJsonValue = (value3) => {
        if (value3 === null)
          return value3;
        const arr = typeof value3 === "string" ? parsePgArray(value3) : value3;
        return this.mapJsonArrayElements(arr, config.customTypeParams.fromJson, this.dimensions);
      };
  }
  mapJsonArrayElements(value3, mapper, depth) {
    if (depth > 0 && Array.isArray(value3))
      return value3.map((v) => v === null ? null : this.mapJsonArrayElements(v, mapper, depth - 1));
    return mapper(value3);
  }
  getSQLType() {
    return this.sqlName;
  }
};
function customType(customTypeParams) {
  return (a, b) => {
    const { name, config } = getColumnNameAndConfig(a, b);
    return new PgCustomColumnBuilder(name, config, customTypeParams);
  };
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/date.common.js
var PgDateColumnBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgDateColumnBaseBuilder";
  defaultNow() {
    return this.default(sql`now()`);
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/date.js
var PgDateBuilder = class extends PgDateColumnBuilder {
  static [entityKind] = "PgDateBuilder";
  constructor(name) {
    super(name, "object date", "PgDate");
  }
  build(table) {
    return new PgDate(table, this.config);
  }
};
var PgDate = class extends PgColumn {
  static [entityKind] = "PgDate";
  codec = "date";
  getSQLType() {
    return "date";
  }
  mapToDriverValue = function(value3) {
    if (typeof value3 === "string")
      return value3;
    return value3.toISOString();
  };
};
var PgDateStringBuilder = class extends PgDateColumnBuilder {
  static [entityKind] = "PgDateStringBuilder";
  constructor(name) {
    super(name, "string date", "PgDateString");
  }
  build(table) {
    return new PgDateString(table, this.config);
  }
};
var PgDateString = class extends PgColumn {
  static [entityKind] = "PgDateString";
  codec = "date:string";
  getSQLType() {
    return "date";
  }
  mapToDriverValue = (value3) => {
    if (typeof value3 === "string")
      return value3;
    return value3.toISOString();
  };
};
function date(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (config?.mode === "date")
    return new PgDateBuilder(name);
  return new PgDateStringBuilder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/double-precision.js
var PgDoublePrecisionBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgDoublePrecisionBuilder";
  constructor(name) {
    super(name, "number double", "PgDoublePrecision");
  }
  build(table) {
    return new PgDoublePrecision(table, this.config);
  }
};
var PgDoublePrecision = class extends PgColumn {
  static [entityKind] = "PgDoublePrecision";
  codec = "float8";
  getSQLType() {
    return "double precision";
  }
};
function doublePrecision(name) {
  return new PgDoublePrecisionBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/inet.js
var PgInetBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgInetBuilder";
  constructor(name) {
    super(name, "string inet", "PgInet");
  }
  build(table) {
    return new PgInet(table, this.config);
  }
};
var PgInet = class extends PgColumn {
  static [entityKind] = "PgInet";
  codec = "inet";
  getSQLType() {
    return "inet";
  }
};
function inet(name) {
  return new PgInetBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/integer.js
var PgIntegerBuilder = class extends PgIntColumnBuilder {
  static [entityKind] = "PgIntegerBuilder";
  constructor(name) {
    super(name, "number int32", "PgInteger");
  }
  build(table) {
    return new PgInteger(table, this.config);
  }
};
var PgInteger = class extends PgColumn {
  static [entityKind] = "PgInteger";
  codec = "int";
  getSQLType() {
    return "integer";
  }
};
function integer(name) {
  return new PgIntegerBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/interval.js
var PgIntervalBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgIntervalBuilder";
  constructor(name, intervalConfig) {
    super(name, "string interval", "PgInterval");
    this.config.intervalConfig = intervalConfig;
  }
  build(table) {
    return new PgInterval(table, this.config);
  }
};
var PgInterval = class extends PgColumn {
  static [entityKind] = "PgInterval";
  codec = "interval";
  fields;
  precision;
  constructor(table, config) {
    super(table, config);
    this.fields = config.intervalConfig.fields;
    this.precision = config.intervalConfig.precision;
  }
  getSQLType() {
    return `interval${this.fields ? ` ${this.fields}` : ""}${this.precision ? `(${this.precision})` : ""}`;
  }
};
function interval(a, b = {}) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgIntervalBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/json.js
var PgJsonBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgJsonBuilder";
  constructor(name) {
    super(name, "object json", "PgJson");
  }
  build(table) {
    return new PgJson(table, this.config);
  }
};
var PgJson = class extends PgColumn {
  static [entityKind] = "PgJson";
  codec = "json";
  constructor(table, config) {
    super(table, config);
  }
  getSQLType() {
    return "json";
  }
};
function json(name) {
  return new PgJsonBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/jsonb.js
var PgJsonbBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgJsonbBuilder";
  constructor(name) {
    super(name, "object json", "PgJsonb");
  }
  build(table) {
    return new PgJsonb(table, this.config);
  }
};
var PgJsonb = class extends PgColumn {
  static [entityKind] = "PgJsonb";
  codec = "jsonb";
  constructor(table, config) {
    super(table, config);
  }
  getSQLType() {
    return "jsonb";
  }
};
function jsonb(name) {
  return new PgJsonbBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/line.js
var PgLineBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgLineBuilder";
  constructor(name) {
    super(name, "array line", "PgLine");
  }
  build(table) {
    return new PgLineTuple(table, this.config);
  }
};
var PgLineTuple = class extends PgColumn {
  static [entityKind] = "PgLine";
  codec = "line:tuple";
  mode = "tuple";
  getSQLType() {
    return "line";
  }
  mapToDriverValue = (value3) => {
    return `{${value3[0]},${value3[1]},${value3[2]}}`;
  };
};
var PgLineABCBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgLineABCBuilder";
  constructor(name) {
    super(name, "object line", "PgLineABC");
  }
  build(table) {
    return new PgLineABC(table, this.config);
  }
};
var PgLineABC = class extends PgColumn {
  static [entityKind] = "PgLineABC";
  codec = "line";
  mode = "abc";
  getSQLType() {
    return "line";
  }
  mapToDriverValue = (value3) => {
    return `{${value3.a},${value3.b},${value3.c}}`;
  };
};
function line(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (!config?.mode || config.mode === "tuple")
    return new PgLineBuilder(name);
  return new PgLineABCBuilder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/macaddr.js
var PgMacaddrBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgMacaddrBuilder";
  constructor(name) {
    super(name, "string macaddr", "PgMacaddr");
  }
  build(table) {
    return new PgMacaddr(table, this.config);
  }
};
var PgMacaddr = class extends PgColumn {
  static [entityKind] = "PgMacaddr";
  codec = "macaddr";
  getSQLType() {
    return "macaddr";
  }
};
function macaddr(name) {
  return new PgMacaddrBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/macaddr8.js
var PgMacaddr8Builder = class extends PgColumnBuilder {
  static [entityKind] = "PgMacaddr8Builder";
  constructor(name) {
    super(name, "string macaddr8", "PgMacaddr8");
  }
  build(table) {
    return new PgMacaddr8(table, this.config);
  }
};
var PgMacaddr8 = class extends PgColumn {
  static [entityKind] = "PgMacaddr8";
  codec = "macaddr8";
  getSQLType() {
    return "macaddr8";
  }
};
function macaddr8(name) {
  return new PgMacaddr8Builder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/numeric.js
var PgNumericBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgNumericBuilder";
  constructor(name, precision, scale) {
    super(name, "string numeric", "PgNumeric");
    this.config.precision = precision;
    this.config.scale = scale;
  }
  build(table) {
    return new PgNumeric(table, this.config);
  }
};
var PgNumeric = class extends PgColumn {
  static [entityKind] = "PgNumeric";
  codec = "numeric";
  precision;
  scale;
  constructor(table, config) {
    super(table, config);
    this.precision = config.precision;
    this.scale = config.scale;
  }
  getSQLType() {
    if (this.precision !== undefined && this.scale !== undefined)
      return `numeric(${this.precision}, ${this.scale})`;
    else if (this.precision === undefined)
      return "numeric";
    else
      return `numeric(${this.precision})`;
  }
};
var PgNumericNumberBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgNumericNumberBuilder";
  constructor(name, precision, scale) {
    super(name, "number", "PgNumericNumber");
    this.config.precision = precision;
    this.config.scale = scale;
  }
  build(table) {
    return new PgNumericNumber(table, this.config);
  }
};
var PgNumericNumber = class extends PgColumn {
  static [entityKind] = "PgNumericNumber";
  codec = "numeric:number";
  precision;
  scale;
  constructor(table, config) {
    super(table, config);
    this.precision = config.precision;
    this.scale = config.scale;
  }
  mapToDriverValue = String;
  getSQLType() {
    if (this.precision !== undefined && this.scale !== undefined)
      return `numeric(${this.precision}, ${this.scale})`;
    else if (this.precision === undefined)
      return "numeric";
    else
      return `numeric(${this.precision})`;
  }
};
var PgNumericBigIntBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgNumericBigIntBuilder";
  constructor(name, precision, scale) {
    super(name, "bigint int64", "PgNumericBigInt");
    this.config.precision = precision;
    this.config.scale = scale;
  }
  build(table) {
    return new PgNumericBigInt(table, this.config);
  }
};
var PgNumericBigInt = class extends PgColumn {
  static [entityKind] = "PgNumericBigInt";
  codec = "numeric:bigint";
  precision;
  scale;
  constructor(table, config) {
    super(table, config);
    this.precision = config.precision;
    this.scale = config.scale;
  }
  mapToDriverValue = String;
  getSQLType() {
    if (this.precision !== undefined && this.scale !== undefined)
      return `numeric(${this.precision}, ${this.scale})`;
    else if (this.precision === undefined)
      return "numeric";
    else
      return `numeric(${this.precision})`;
  }
};
function numeric(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  const mode = config?.mode;
  return mode === "number" ? new PgNumericNumberBuilder(name, config?.precision, config?.scale) : mode === "bigint" ? new PgNumericBigIntBuilder(name, config?.precision, config?.scale) : new PgNumericBuilder(name, config?.precision, config?.scale);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/point.js
var PgPointTupleBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgPointTupleBuilder";
  constructor(name) {
    super(name, "array point", "PgPointTuple");
  }
  build(table) {
    return new PgPointTuple(table, this.config);
  }
};
var PgPointTuple = class extends PgColumn {
  static [entityKind] = "PgPointTuple";
  codec = "point:tuple";
  mode = "tuple";
  getSQLType() {
    return "point";
  }
  mapToDriverValue = (value3) => {
    return `(${value3[0]},${value3[1]})`;
  };
};
var PgPointObjectBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgPointObjectBuilder";
  constructor(name) {
    super(name, "object point", "PgPointObject");
  }
  build(table) {
    return new PgPointObject(table, this.config);
  }
};
var PgPointObject = class extends PgColumn {
  static [entityKind] = "PgPointObject";
  codec = "point";
  mode = "xy";
  getSQLType() {
    return "point";
  }
  mapToDriverValue = (value3) => {
    return `(${value3.x},${value3.y})`;
  };
};
function point(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (!config?.mode || config.mode === "tuple")
    return new PgPointTupleBuilder(name);
  return new PgPointObjectBuilder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/postgis_extension/geometry.js
var PgGeometryBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgGeometryBuilder";
  constructor(name, srid) {
    super(name, "array geometry", "PgGeometry");
    this.config.srid = srid;
  }
  build(table) {
    return new PgGeometry(table, this.config);
  }
};
var PgGeometry = class extends PgColumn {
  static [entityKind] = "PgGeometry";
  codec = "geometry:tuple";
  srid = this.config.srid;
  mode = "tuple";
  getSQLType() {
    return `geometry(point${this.srid === undefined ? "" : `,${this.srid}`})`;
  }
  mapToDriverValue = (value3) => {
    return `point(${value3[0]} ${value3[1]})`;
  };
};
var PgGeometryObjectBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgGeometryObjectBuilder";
  constructor(name, srid) {
    super(name, "object geometry", "PgGeometryObject");
    this.config.srid = srid;
  }
  build(table) {
    return new PgGeometryObject(table, this.config);
  }
};
var PgGeometryObject = class extends PgColumn {
  static [entityKind] = "PgGeometryObject";
  codec = "geometry";
  srid = this.config.srid;
  mode = "object";
  getSQLType() {
    return `geometry(point${this.srid === undefined ? "" : `,${this.srid}`})`;
  }
  mapToDriverValue = (value3) => {
    return `point(${value3.x} ${value3.y})`;
  };
};
function geometry(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (!config?.mode || config.mode === "tuple")
    return new PgGeometryBuilder(name, config?.srid);
  return new PgGeometryObjectBuilder(name, config?.srid);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/real.js
var PgRealBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgRealBuilder";
  constructor(name, length) {
    super(name, "number float", "PgReal");
    this.config.length = length;
  }
  build(table) {
    return new PgReal(table, this.config);
  }
};
var PgReal = class extends PgColumn {
  static [entityKind] = "PgReal";
  codec = "float4";
  constructor(table, config) {
    super(table, config);
  }
  getSQLType() {
    return "real";
  }
};
function real(name) {
  return new PgRealBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/serial.js
var PgSerialBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgSerialBuilder";
  constructor(name) {
    super(name, "number int32", "PgSerial");
    this.config.hasDefault = true;
    this.config.notNull = true;
  }
  build(table) {
    return new PgSerial(table, this.config);
  }
};
var PgSerial = class extends PgColumn {
  static [entityKind] = "PgSerial";
  codec = "serial";
  getSQLType() {
    return "serial";
  }
};
function serial(name) {
  return new PgSerialBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/smallint.js
var PgSmallIntBuilder = class extends PgIntColumnBuilder {
  static [entityKind] = "PgSmallIntBuilder";
  constructor(name) {
    super(name, "number int16", "PgSmallInt");
  }
  build(table) {
    return new PgSmallInt(table, this.config);
  }
};
var PgSmallInt = class extends PgColumn {
  static [entityKind] = "PgSmallInt";
  codec = "smallint";
  getSQLType() {
    return "smallint";
  }
};
function smallint(name) {
  return new PgSmallIntBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/smallserial.js
var PgSmallSerialBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgSmallSerialBuilder";
  constructor(name) {
    super(name, "number int16", "PgSmallSerial");
    this.config.hasDefault = true;
    this.config.notNull = true;
  }
  build(table) {
    return new PgSmallSerial(table, this.config);
  }
};
var PgSmallSerial = class extends PgColumn {
  static [entityKind] = "PgSmallSerial";
  codec = "smallserial";
  getSQLType() {
    return "smallserial";
  }
};
function smallserial(name) {
  return new PgSmallSerialBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/text.js
var PgTextBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgTextBuilder";
  constructor(name, config) {
    super(name, config.enum?.length ? "string enum" : "string", "PgText");
    this.config.enumValues = config.enum;
  }
  build(table) {
    return new PgText(table, this.config, this.config.enumValues);
  }
};
var PgText = class extends PgColumn {
  static [entityKind] = "PgText";
  enumValues;
  codec = "text";
  constructor(table, config, enumValues) {
    super(table, config);
    this.enumValues = enumValues;
  }
  getSQLType() {
    return "text";
  }
};
function text(a, b = {}) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgTextBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/time.js
var PgTimeBuilder = class extends PgDateColumnBuilder {
  static [entityKind] = "PgTimeBuilder";
  constructor(name, withTimezone, precision) {
    super(name, "string time", "PgTime");
    this.withTimezone = withTimezone;
    this.precision = precision;
    this.config.withTimezone = withTimezone;
    this.config.precision = precision;
  }
  build(table) {
    return new PgTime(table, this.config);
  }
};
var PgTime = class extends PgColumn {
  static [entityKind] = "PgTime";
  codec = "time";
  withTimezone;
  precision;
  constructor(table, config) {
    super(table, config);
    this.withTimezone = config.withTimezone;
    this.precision = config.precision;
  }
  getSQLType() {
    return `time${this.precision === undefined ? "" : `(${this.precision})`}${this.withTimezone ? " with time zone" : ""}`;
  }
};
function time(a, b = {}) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgTimeBuilder(name, config.withTimezone ?? false, config.precision);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/timestamp.js
var PgTimestampBuilder = class extends PgDateColumnBuilder {
  static [entityKind] = "PgTimestampBuilder";
  constructor(name, withTimezone, precision) {
    super(name, "object date", "PgTimestamp");
    this.config.withTimezone = withTimezone;
    this.config.precision = precision;
  }
  build(table) {
    return new PgTimestamp(table, this.config);
  }
};
var PgTimestamp = class extends PgColumn {
  static [entityKind] = "PgTimestamp";
  codec;
  withTimezone;
  precision;
  constructor(table, config) {
    super(table, config);
    this.withTimezone = config.withTimezone;
    this.precision = config.precision;
    this.codec = this.withTimezone ? "timestamptz" : "timestamp";
  }
  getSQLType() {
    return `timestamp${this.precision === undefined ? "" : ` (${this.precision})`}${this.withTimezone ? " with time zone" : ""}`;
  }
  mapToDriverValue = (value3) => {
    if (typeof value3 === "string")
      return value3;
    return value3.toISOString();
  };
};
var PgTimestampStringBuilder = class extends PgDateColumnBuilder {
  static [entityKind] = "PgTimestampStringBuilder";
  constructor(name, withTimezone, precision) {
    super(name, "string timestamp", "PgTimestampString");
    this.config.withTimezone = withTimezone;
    this.config.precision = precision;
  }
  build(table) {
    return new PgTimestampString(table, this.config);
  }
};
var PgTimestampString = class extends PgColumn {
  static [entityKind] = "PgTimestampString";
  codec;
  withTimezone;
  precision;
  constructor(table, config) {
    super(table, config);
    this.withTimezone = config.withTimezone;
    this.precision = config.precision;
    this.codec = this.withTimezone ? "timestamptz:string" : "timestamp:string";
  }
  getSQLType() {
    return `timestamp${this.precision === undefined ? "" : `(${this.precision})`}${this.withTimezone ? " with time zone" : ""}`;
  }
  mapToDriverValue = (value3) => {
    if (typeof value3 === "string")
      return value3;
    return value3.toISOString();
  };
};
function timestamp(a, b = {}) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (config?.mode === "string")
    return new PgTimestampStringBuilder(name, config.withTimezone ?? false, config.precision);
  return new PgTimestampBuilder(name, config?.withTimezone ?? false, config?.precision);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/uuid.js
var PgUUIDBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgUUIDBuilder";
  constructor(name) {
    super(name, "string uuid", "PgUUID");
  }
  defaultRandom() {
    return this.default(sql`gen_random_uuid()`);
  }
  build(table) {
    return new PgUUID(table, this.config);
  }
};
var PgUUID = class extends PgColumn {
  static [entityKind] = "PgUUID";
  codec = "uuid";
  getSQLType() {
    return "uuid";
  }
};
function uuid(name) {
  return new PgUUIDBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/varchar.js
var PgVarcharBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgVarcharBuilder";
  constructor(name, config) {
    super(name, config.enum?.length ? "string enum" : "string", "PgVarchar");
    this.config.length = config.length;
    this.config.enumValues = config.enum;
  }
  build(table) {
    return new PgVarchar(table, this.config);
  }
};
var PgVarchar = class extends PgColumn {
  static [entityKind] = "PgVarchar";
  codec = "varchar";
  enumValues;
  constructor(table, config) {
    super(table, config);
    this.enumValues = config.enumValues;
  }
  getSQLType() {
    return this.length === undefined ? `varchar` : `varchar(${this.length})`;
  }
};
function varchar(a, b = {}) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgVarcharBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/vector_extension/bit.js
var PgBinaryVectorBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgBinaryVectorBuilder";
  constructor(name, config) {
    super(name, "string binary", "PgBinaryVector");
    this.config.length = config.dimensions;
    this.config.isLengthExact = true;
  }
  build(table) {
    return new PgBinaryVector(table, this.config);
  }
};
var PgBinaryVector = class extends PgColumn {
  static [entityKind] = "PgBinaryVector";
  codec = "bit";
  getSQLType() {
    return `bit(${this.length})`;
  }
};
function bit(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgBinaryVectorBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/vector_extension/halfvec.js
var PgHalfVectorBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgHalfVectorBuilder";
  constructor(name, config) {
    super(name, "array halfvector", "PgHalfVector");
    this.config.length = config.dimensions;
    this.config.isLengthExact = true;
  }
  build(table) {
    return new PgHalfVector(table, this.config);
  }
};
var PgHalfVector = class extends PgColumn {
  static [entityKind] = "PgHalfVector";
  codec = "halfvec";
  getSQLType() {
    return `halfvec(${this.length})`;
  }
  mapToDriverValue = (value3) => {
    return JSON.stringify(value3);
  };
};
function halfvec(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgHalfVectorBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/vector_extension/sparsevec.js
var PgSparseVectorBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgSparseVectorBuilder";
  constructor(name, config) {
    super(name, "string sparsevec", "PgSparseVector");
    this.config.vectorDimensions = config.dimensions;
  }
  build(table) {
    return new PgSparseVector(table, this.config);
  }
};
var PgSparseVector = class extends PgColumn {
  static [entityKind] = "PgSparseVector";
  codec = "sparsevec";
  vectorDimensions = this.config.vectorDimensions;
  getSQLType() {
    return `sparsevec(${this.vectorDimensions})`;
  }
};
function sparsevec(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgSparseVectorBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/vector_extension/vector.js
var PgVectorBuilder = class extends PgColumnBuilder {
  static [entityKind] = "PgVectorBuilder";
  constructor(name, config) {
    super(name, "array vector", "PgVector");
    this.config.length = config.dimensions;
    this.config.isLengthExact = true;
  }
  build(table) {
    return new PgVector(table, this.config);
  }
};
var PgVector = class extends PgColumn {
  static [entityKind] = "PgVector";
  codec = "vector";
  getSQLType() {
    return `vector(${this.length})`;
  }
  mapToDriverValue = (value3) => {
    return JSON.stringify(value3);
  };
};
function vector(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  return new PgVectorBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/columns/all.js
function getPgColumnBuilders() {
  return {
    bigint,
    bigserial,
    boolean: boolean2,
    char,
    cidr,
    customType,
    date,
    doublePrecision,
    inet,
    integer,
    interval,
    json,
    jsonb,
    line,
    macaddr,
    macaddr8,
    numeric,
    point,
    geometry,
    real,
    serial,
    smallint,
    smallserial,
    text,
    time,
    timestamp,
    uuid,
    varchar,
    bit,
    halfvec,
    sparsevec,
    vector
  };
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/casing.js
function toSnakeCase(input) {
  return (input.replace(/['\u2019]/g, "").match(/[\da-z]+|[A-Z]+(?![a-z])|[A-Z][\da-z]+/g) ?? []).map((word) => word.toLowerCase()).join("_");
}
function toCamelCase(input) {
  return (input.replace(/['\u2019]/g, "").match(/[\da-z]+|[A-Z]+(?![a-z])|[A-Z][\da-z]+/g) ?? []).reduce((acc, word, i) => {
    return acc + (i === 0 ? word.toLowerCase() : `${word[0].toUpperCase()}${word.slice(1)}`);
  }, "");
}
function getCasingFn(casing) {
  if (casing === "snake_case")
    return toSnakeCase;
  if (casing === "camelCase")
    return toCamelCase;
  return (name) => name;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/table.js
var InlineForeignKeys = Symbol.for("drizzle:PgInlineForeignKeys");
var EnableRLS = Symbol.for("drizzle:EnableRLS");
var PgTable = class extends Table {
  static [entityKind] = "PgTable";
  static Symbol = Object.assign({}, Table.Symbol, {
    InlineForeignKeys,
    EnableRLS
  });
  [InlineForeignKeys] = [];
  [EnableRLS] = false;
  [Table.Symbol.ExtraConfigBuilder] = undefined;
  [Table.Symbol.ExtraConfigColumns] = {};
};
function pgTableWithSchema(name, columns, extraConfig, schema2, casing, baseName = name) {
  const casingFn = getCasingFn(casing);
  const rawTable = new PgTable(name, schema2, baseName);
  const parsedColumns = typeof columns === "function" ? columns(getPgColumnBuilders()) : columns;
  const builtColumns = Object.fromEntries(Object.entries(parsedColumns).map(([name2, colBuilderBase]) => {
    const colBuilder = colBuilderBase;
    colBuilder.setName(name2, casingFn);
    const column = colBuilder.build(rawTable).postBuild();
    rawTable[InlineForeignKeys].push(...colBuilder.buildForeignKeys(column, rawTable));
    return [name2, column];
  }));
  const builtColumnsForExtraConfig = Object.fromEntries(Object.entries(parsedColumns).map(([name2, colBuilderBase]) => {
    const colBuilder = colBuilderBase;
    colBuilder.setName(name2, casingFn);
    return [name2, colBuilder.buildExtraConfigColumn(rawTable)];
  }));
  const table = Object.assign(rawTable, builtColumns);
  table[Table.Symbol.Columns] = builtColumns;
  table[Table.Symbol.ExtraConfigColumns] = builtColumnsForExtraConfig;
  if (extraConfig)
    table[PgTable.Symbol.ExtraConfigBuilder] = extraConfig;
  return Object.assign(table, { enableRLS: () => {
    table[PgTable.Symbol.EnableRLS] = true;
    return table;
  } });
}
function pgTableWithCasing(casing) {
  const pgTableInternal = (name, columns, extraConfig) => {
    return pgTableWithSchema(name, columns, extraConfig, undefined, casing);
  };
  const pgTableWithRLS = (name, columns, extraConfig) => {
    const table = pgTableWithSchema(name, columns, extraConfig, undefined, casing);
    table[EnableRLS] = true;
    return table;
  };
  return Object.assign(pgTableInternal, { withRLS: pgTableWithRLS });
}
var pgTable = pgTableWithCasing(undefined);

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/pg-core/primary-keys.js
var PrimaryKeyBuilder = class {
  static [entityKind] = "PgPrimaryKeyBuilder";
  columns;
  name;
  constructor(columns, name) {
    this.columns = columns;
    this.name = name;
  }
  build(table) {
    return new PrimaryKey(table, this.columns, this.name);
  }
};
var PrimaryKey = class {
  static [entityKind] = "PgPrimaryKey";
  columns;
  name;
  isNameExplicit;
  constructor(table, columns, name) {
    this.table = table;
    this.columns = columns;
    this.name = name;
    this.isNameExplicit = !!name;
  }
  getName() {
    return this.name ?? `${this.table[PgTable.Symbol.Name]}_${this.columns.map((column) => column.name).join("_")}_pk`;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/_relations.js
var Relation2 = class {
  static [entityKind] = "Relation";
  referencedTableName;
  fieldName;
  constructor(sourceTable, referencedTable, relationName) {
    this.sourceTable = sourceTable;
    this.referencedTable = referencedTable;
    this.relationName = relationName;
    this.referencedTableName = referencedTable[Table.Symbol.Name];
  }
};
var Relations = class {
  static [entityKind] = "Relations";
  constructor(table, config) {
    this.table = table;
    this.config = config;
  }
};
var One2 = class One3 extends Relation2 {
  static [entityKind] = "One";
  constructor(sourceTable, referencedTable, config, isNullable) {
    super(sourceTable, referencedTable, config?.relationName);
    this.config = config;
    this.isNullable = isNullable;
  }
  withFieldName(fieldName) {
    const relation = new One3(this.sourceTable, this.referencedTable, this.config, this.isNullable);
    relation.fieldName = fieldName;
    return relation;
  }
};
var Many = class Many2 extends Relation2 {
  static [entityKind] = "Many";
  constructor(sourceTable, referencedTable, config) {
    super(sourceTable, referencedTable, config?.relationName);
    this.config = config;
  }
  withFieldName(fieldName) {
    const relation = new Many2(this.sourceTable, this.referencedTable, this.config);
    relation.fieldName = fieldName;
    return relation;
  }
};
function getOperators() {
  return {
    and,
    between,
    eq,
    exists,
    gt,
    gte,
    ilike,
    inArray,
    isNull,
    isNotNull,
    like,
    lt,
    lte,
    ne,
    not,
    notBetween,
    notExists,
    notLike,
    notIlike,
    notInArray,
    or,
    sql
  };
}
function getOrderByOperators() {
  return {
    sql,
    asc,
    desc
  };
}
function extractTablesRelationalConfig(schema2, configHelpers) {
  if (Object.keys(schema2).length === 1 && "default" in schema2 && !is2(schema2["default"], Table))
    schema2 = schema2["default"];
  const tableNamesMap = {};
  const relationsBuffer = {};
  const tablesConfig = {};
  for (const [key, value3] of Object.entries(schema2))
    if (is2(value3, Table)) {
      const dbName = getTableUniqueName(value3);
      const bufferedRelations = relationsBuffer[dbName];
      tableNamesMap[dbName] = key;
      tablesConfig[key] = {
        tsName: key,
        dbName: value3[Table.Symbol.Name],
        schema: value3[Table.Symbol.Schema],
        columns: value3[Table.Symbol.Columns],
        relations: bufferedRelations?.relations ?? {},
        primaryKey: bufferedRelations?.primaryKey ?? []
      };
      for (const column of Object.values(value3[Table.Symbol.Columns]))
        if (column.primary)
          tablesConfig[key].primaryKey.push(column);
      const extraConfig = value3[Table.Symbol.ExtraConfigBuilder]?.(value3[Table.Symbol.ExtraConfigColumns]);
      if (extraConfig) {
        for (const configEntry of Object.values(extraConfig))
          if (is2(configEntry, PrimaryKeyBuilder))
            tablesConfig[key].primaryKey.push(...configEntry.columns);
      }
    } else if (is2(value3, Relations)) {
      const dbName = getTableUniqueName(value3.table);
      const tableName = tableNamesMap[dbName];
      const relations = value3.config(configHelpers(value3.table));
      for (const [relationName, relation] of Object.entries(relations))
        if (tableName) {
          const tableConfig = tablesConfig[tableName];
          tableConfig.relations[relationName] = relation;
        } else {
          if (!(dbName in relationsBuffer))
            relationsBuffer[dbName] = { relations: {} };
          relationsBuffer[dbName].relations[relationName] = relation;
        }
    }
  return {
    tables: tablesConfig,
    tableNamesMap
  };
}
function createOne(sourceTable) {
  return function one(table, config) {
    return new One2(sourceTable, table, config, config?.fields.reduce((res, f) => res && f.notNull, true) ?? false);
  };
}
function createMany(sourceTable) {
  return function many(referencedTable, config) {
    return new Many(sourceTable, referencedTable, config);
  };
}
function normalizeRelation(schema2, tableNamesMap, relation) {
  if (is2(relation, One2) && relation.config)
    return {
      fields: relation.config.fields,
      references: relation.config.references
    };
  const referencedTableTsName = tableNamesMap[getTableUniqueName(relation.referencedTable)];
  if (!referencedTableTsName)
    throw new Error(`Table "${relation.referencedTable[Table.Symbol.Name]}" not found in schema`);
  const referencedTableConfig = schema2[referencedTableTsName];
  if (!referencedTableConfig)
    throw new Error(`Table "${referencedTableTsName}" not found in schema`);
  const sourceTable = relation.sourceTable;
  const sourceTableTsName = tableNamesMap[getTableUniqueName(sourceTable)];
  if (!sourceTableTsName)
    throw new Error(`Table "${sourceTable[Table.Symbol.Name]}" not found in schema`);
  const reverseRelations = [];
  for (const referencedTableRelation of Object.values(referencedTableConfig.relations))
    if (relation.relationName && relation !== referencedTableRelation && referencedTableRelation.relationName === relation.relationName || !relation.relationName && referencedTableRelation.referencedTable === relation.sourceTable)
      reverseRelations.push(referencedTableRelation);
  if (reverseRelations.length > 1)
    throw relation.relationName ? /* @__PURE__ */ new Error(`There are multiple relations with name "${relation.relationName}" in table "${referencedTableTsName}"`) : /* @__PURE__ */ new Error(`There are multiple relations between "${referencedTableTsName}" and "${relation.sourceTable[Table.Symbol.Name]}". Please specify relation name`);
  if (reverseRelations[0] && is2(reverseRelations[0], One2) && reverseRelations[0].config)
    return {
      fields: reverseRelations[0].config.references,
      references: reverseRelations[0].config.fields
    };
  throw new Error(`There is not enough information to infer relation "${sourceTableTsName}.${relation.fieldName}"`);
}
function createTableRelationsHelpers(sourceTable) {
  return {
    one: createOne(sourceTable),
    many: createMany(sourceTable)
  };
}
function mapRelationalRow2(tablesConfig, tableConfig, row, buildQueryResultSelection, mapColumnValue = (value3) => value3) {
  const result3 = {};
  for (const [selectionItemIndex, selectionItem] of buildQueryResultSelection.entries())
    if (selectionItem.isJson) {
      const relation = tableConfig.relations[selectionItem.tsKey];
      const rawSubRows = row[selectionItemIndex];
      const subRows = typeof rawSubRows === "string" ? JSON.parse(rawSubRows) : rawSubRows;
      result3[selectionItem.tsKey] = is2(relation, One2) ? subRows && mapRelationalRow2(tablesConfig, tablesConfig[selectionItem.relationTableTsKey], subRows, selectionItem.selection, mapColumnValue) : subRows.map((subRow) => mapRelationalRow2(tablesConfig, tablesConfig[selectionItem.relationTableTsKey], subRow, selectionItem.selection, mapColumnValue));
    } else {
      const value3 = mapColumnValue(row[selectionItemIndex]);
      const field = selectionItem.field;
      let decoder;
      if (is2(field, Column))
        decoder = field;
      else if (is2(field, SQL))
        decoder = field.decoder;
      else
        decoder = field.sql.decoder;
      result3[selectionItem.tsKey] = value3 === null ? null : decoder.mapFromDriverValue(value3);
    }
  return result3;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/query-promise.js
var QueryPromise = class {
  static [entityKind] = "QueryPromise";
  [Symbol.toStringTag] = "QueryPromise";
  catch(onRejected) {
    return this.then(undefined, onRejected);
  }
  finally(onFinally) {
    return this.then((value3) => {
      onFinally?.();
      return value3;
    }, (reason) => {
      onFinally?.();
      throw reason;
    });
  }
  then(onFulfilled, onRejected) {
    return this.execute().then(onFulfilled, onRejected);
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/_query.js
var _RelationalQueryBuilder = class {
  static [entityKind] = "SQLiteAsyncRelationalQueryBuilder";
  constructor(mode, fullSchema, schema2, tableNamesMap, table, tableConfig, dialect, session) {
    this.mode = mode;
    this.fullSchema = fullSchema;
    this.schema = schema2;
    this.tableNamesMap = tableNamesMap;
    this.table = table;
    this.tableConfig = tableConfig;
    this.dialect = dialect;
    this.session = session;
  }
  findMany(config) {
    return this.mode === "sync" ? new SQLiteSyncRelationalQuery(this.fullSchema, this.schema, this.tableNamesMap, this.table, this.tableConfig, this.dialect, this.session, config ? config : {}, "many") : new SQLiteRelationalQuery(this.fullSchema, this.schema, this.tableNamesMap, this.table, this.tableConfig, this.dialect, this.session, config ? config : {}, "many");
  }
  findFirst(config) {
    return this.mode === "sync" ? new SQLiteSyncRelationalQuery(this.fullSchema, this.schema, this.tableNamesMap, this.table, this.tableConfig, this.dialect, this.session, config ? {
      ...config,
      limit: 1
    } : { limit: 1 }, "first") : new SQLiteRelationalQuery(this.fullSchema, this.schema, this.tableNamesMap, this.table, this.tableConfig, this.dialect, this.session, config ? {
      ...config,
      limit: 1
    } : { limit: 1 }, "first");
  }
};
var SQLiteRelationalQuery = class extends QueryPromise {
  static [entityKind] = "SQLiteAsyncRelationalQuery";
  mode;
  constructor(fullSchema, schema2, tableNamesMap, table, tableConfig, dialect, session, config, mode) {
    super();
    this.fullSchema = fullSchema;
    this.schema = schema2;
    this.tableNamesMap = tableNamesMap;
    this.table = table;
    this.tableConfig = tableConfig;
    this.dialect = dialect;
    this.session = session;
    this.config = config;
    this.mode = mode;
  }
  getSQL() {
    return this.dialect._buildRelationalQuery({
      fullSchema: this.fullSchema,
      schema: this.schema,
      tableNamesMap: this.tableNamesMap,
      table: this.table,
      tableConfig: this.tableConfig,
      queryConfig: this.config,
      tableAlias: this.tableConfig.tsName
    }).sql;
  }
  _prepare(isOneTimeQuery = false) {
    const { query, builtQuery } = this._toSQL();
    return this.session[isOneTimeQuery ? "prepareOneTimeQuery" : "prepareQuery"](builtQuery, undefined, this.mode === "first" ? "get" : "all", (rawRows, mapColumnValue) => {
      const rows = rawRows.map((row) => mapRelationalRow2(this.schema, this.tableConfig, row, query.selection, mapColumnValue));
      if (this.mode === "first")
        return rows[0];
      return rows;
    });
  }
  prepare() {
    return this._prepare(false);
  }
  _toSQL() {
    const query = this.dialect._buildRelationalQuery({
      fullSchema: this.fullSchema,
      schema: this.schema,
      tableNamesMap: this.tableNamesMap,
      table: this.table,
      tableConfig: this.tableConfig,
      queryConfig: this.config,
      tableAlias: this.tableConfig.tsName
    });
    return {
      query,
      builtQuery: this.dialect.sqlToQuery(query.sql)
    };
  }
  toSQL() {
    return this._toSQL().builtQuery;
  }
  executeRaw() {
    if (this.mode === "first")
      return this._prepare(false).get();
    return this._prepare(false).all();
  }
  async execute() {
    return this.executeRaw();
  }
};
var SQLiteSyncRelationalQuery = class extends SQLiteRelationalQuery {
  static [entityKind] = "SQLiteSyncRelationalQuery";
  sync() {
    return this.executeRaw();
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/count.js
var SQLiteCountBuilder = class SQLiteCountBuilder2 extends SQL {
  sql;
  static [entityKind] = "SQLiteCountBuilderAsync";
  [Symbol.toStringTag] = "SQLiteCountBuilderAsync";
  session;
  static buildEmbeddedCount(source, filters) {
    return sql`(select count(*) from ${source}${sql.raw(" where ").if(filters)}${filters})`;
  }
  static buildCount(source, filters) {
    return sql`select count(*) from ${source}${sql.raw(" where ").if(filters)}${filters}`;
  }
  constructor(params) {
    super(SQLiteCountBuilder2.buildEmbeddedCount(params.source, params.filters).queryChunks);
    this.params = params;
    this.session = params.session;
    this.sql = SQLiteCountBuilder2.buildCount(params.source, params.filters);
  }
  then(onfulfilled, onrejected) {
    return Promise.resolve(this.session.count(this.sql)).then(onfulfilled, onrejected);
  }
  catch(onRejected) {
    return this.then(undefined, onRejected);
  }
  finally(onFinally) {
    return this.then((value3) => {
      onFinally?.();
      return value3;
    }, (reason) => {
      onFinally?.();
      throw reason;
    });
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/query.js
var RelationalQueryBuilder = class {
  static [entityKind] = "SQLiteAsyncRelationalQueryBuilderV2";
  constructor(mode, schema2, table, tableConfig, dialect, session, rowMode, forbidJsonb) {
    this.mode = mode;
    this.schema = schema2;
    this.table = table;
    this.tableConfig = tableConfig;
    this.dialect = dialect;
    this.session = session;
    this.rowMode = rowMode;
    this.forbidJsonb = forbidJsonb;
  }
  findMany(config) {
    return this.mode === "sync" ? new SQLiteSyncRelationalQuery2(this.schema, this.table, this.tableConfig, this.dialect, this.session, config ?? true, "many", this.rowMode, this.forbidJsonb) : new SQLiteRelationalQuery2(this.schema, this.table, this.tableConfig, this.dialect, this.session, config ?? true, "many", this.rowMode, this.forbidJsonb);
  }
  findFirst(config) {
    return this.mode === "sync" ? new SQLiteSyncRelationalQuery2(this.schema, this.table, this.tableConfig, this.dialect, this.session, config ?? true, "first", this.rowMode, this.forbidJsonb) : new SQLiteRelationalQuery2(this.schema, this.table, this.tableConfig, this.dialect, this.session, config ?? true, "first", this.rowMode, this.forbidJsonb);
  }
};
var SQLiteRelationalQuery2 = class extends QueryPromise {
  static [entityKind] = "SQLiteAsyncRelationalQueryV2";
  mode;
  table;
  constructor(schema2, table, tableConfig, dialect, session, config, mode, rowMode, forbidJsonb) {
    super();
    this.schema = schema2;
    this.tableConfig = tableConfig;
    this.dialect = dialect;
    this.session = session;
    this.config = config;
    this.rowMode = rowMode;
    this.forbidJsonb = forbidJsonb;
    this.mode = mode;
    this.table = table;
  }
  getSQL() {
    return this.dialect.buildRelationalQuery({
      schema: this.schema,
      table: this.table,
      tableConfig: this.tableConfig,
      queryConfig: this.config,
      mode: this.mode,
      jsonb: this.forbidJsonb ? sql`json` : sql`jsonb`
    }).sql;
  }
  _prepare(isOneTimeQuery = true) {
    const { query, builtQuery } = this._toSQL();
    return this.session[isOneTimeQuery ? "prepareOneTimeRelationalQuery" : "prepareRelationalQuery"](builtQuery, undefined, this.mode === "first" ? "get" : "all", makeDefaultRqbMapper({
      isFirst: this.mode === "first",
      parseJson: !this.rowMode,
      parseJsonIfString: false,
      rootJsonMappers: true,
      selection: query.selection
    }), {
      isFirst: this.mode === "first",
      parseJson: !this.rowMode,
      parseJsonIfString: false,
      rootJsonMappers: true,
      selection: query.selection
    });
  }
  prepare() {
    return this._prepare(false);
  }
  _getQuery() {
    const jsonb2 = this.forbidJsonb ? sql`json` : sql`jsonb`;
    const query = this.dialect.buildRelationalQuery({
      schema: this.schema,
      table: this.table,
      tableConfig: this.tableConfig,
      queryConfig: this.config,
      mode: this.mode,
      isNested: this.rowMode,
      jsonb: jsonb2
    });
    if (this.rowMode)
      query.sql = sql`select json_object(${sql.join(query.selection.map((s) => {
        return sql`${sql.raw(this.dialect.escapeString(s.key))}, ${s.selection ? sql`${jsonb2}(${sql.identifier(s.key)})` : sql.identifier(s.key)}`;
      }), sql`, `)}) as ${sql.identifier("r")} from (${query.sql}) as ${sql.identifier("t")}`;
    return query;
  }
  _toSQL() {
    const query = this._getQuery();
    return {
      query,
      builtQuery: this.dialect.sqlToQuery(query.sql)
    };
  }
  toSQL() {
    return this._toSQL().builtQuery;
  }
  executeRaw() {
    if (this.mode === "first")
      return this._prepare().get();
    return this._prepare().all();
  }
  async execute() {
    return this.executeRaw();
  }
};
var SQLiteSyncRelationalQuery2 = class extends SQLiteRelationalQuery2 {
  static [entityKind] = "SQLiteSyncRelationalQueryV2";
  sync() {
    return this.executeRaw();
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/raw.js
var SQLiteRaw = class extends QueryPromise {
  static [entityKind] = "SQLiteRaw";
  config;
  constructor(execute, getSQL, action, dialect, mapBatchResult) {
    super();
    this.execute = execute;
    this.getSQL = getSQL;
    this.dialect = dialect;
    this.mapBatchResult = mapBatchResult;
    this.config = { action };
  }
  getQuery() {
    return {
      ...this.dialect.sqlToQuery(this.getSQL()),
      method: this.config.action
    };
  }
  mapResult(result3, isFromBatch) {
    return isFromBatch ? this.mapBatchResult(result3) : result3;
  }
  _prepare() {
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/selection-proxy.js
var SelectionProxyHandler = class SelectionProxyHandler2 {
  static [entityKind] = "SelectionProxyHandler";
  config;
  constructor(config) {
    this.config = { ...config };
  }
  get(subquery, prop) {
    if (prop === "_")
      return {
        ...subquery["_"],
        selectedFields: new Proxy(subquery._.selectedFields, this)
      };
    if (prop === ViewBaseConfig)
      return {
        ...subquery[ViewBaseConfig],
        selectedFields: new Proxy(subquery[ViewBaseConfig].selectedFields, this)
      };
    if (typeof prop === "symbol")
      return subquery[prop];
    const value3 = (is2(subquery, Subquery) ? subquery._.selectedFields : is2(subquery, View) ? subquery[ViewBaseConfig].selectedFields : subquery)[prop];
    if (is2(value3, SQL.Aliased)) {
      if (this.config.sqlAliasedBehavior === "sql" && !value3.isSelectionField)
        return value3.sql;
      const newValue = value3.clone();
      newValue.isSelectionField = true;
      newValue.origin = this.config.alias;
      return newValue;
    }
    if (is2(value3, SQL)) {
      if (this.config.sqlBehavior === "sql")
        return value3;
      throw new Error(`You tried to reference "${prop}" field from a subquery, which is a raw SQL field, but it doesn't have an alias declared. Please add an alias to the field using ".as('alias')" method.`);
    }
    if (is2(value3, Column)) {
      if (this.config.alias)
        return new Proxy(value3, new ColumnTableAliasProxyHandler(new Proxy(value3.table, new TableAliasProxyHandler(this.config.alias, this.config.replaceOriginalName ?? false, true)), true));
      return value3;
    }
    if (typeof value3 !== "object" || value3 === null)
      return value3;
    return new Proxy(value3, new SelectionProxyHandler2(this.config));
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/view-base.js
var SQLiteViewBase = class extends View {
  static [entityKind] = "SQLiteViewBase";
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/foreign-keys.js
var ForeignKeyBuilder2 = class {
  static [entityKind] = "SQLiteForeignKeyBuilder";
  reference;
  _onUpdate;
  _onDelete;
  constructor(config, actions) {
    this.reference = () => {
      const { name, columns, foreignColumns } = config();
      return {
        name,
        columns,
        foreignTable: foreignColumns[0].table,
        foreignColumns
      };
    };
    if (actions) {
      this._onUpdate = actions.onUpdate;
      this._onDelete = actions.onDelete;
    }
  }
  onUpdate(action) {
    this._onUpdate = action;
    return this;
  }
  onDelete(action) {
    this._onDelete = action;
    return this;
  }
  build(table) {
    return new ForeignKey2(table, this);
  }
};
var ForeignKey2 = class {
  static [entityKind] = "SQLiteForeignKey";
  reference;
  onUpdate;
  onDelete;
  constructor(table, builder) {
    this.table = table;
    this.reference = builder.reference;
    this.onUpdate = builder._onUpdate;
    this.onDelete = builder._onDelete;
  }
  getName() {
    const { name, columns, foreignColumns } = this.reference();
    const columnNames = columns.map((column) => column.name);
    const foreignColumnNames = foreignColumns.map((column) => column.name);
    const chunks = [
      this.table[TableName],
      ...columnNames,
      foreignColumns[0].table[TableName],
      ...foreignColumnNames
    ];
    return name ?? `${chunks.join("_")}_fk`;
  }
  isNameExplicit() {
    return !!this.reference().name;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/column-builder.js
var ColumnBuilder = class {
  static [entityKind] = "ColumnBuilder";
  config;
  constructor(name, dataType, columnType) {
    this.config = {
      name,
      keyAsName: name === "",
      notNull: false,
      default: undefined,
      hasDefault: false,
      primaryKey: false,
      isUnique: false,
      uniqueName: undefined,
      uniqueType: undefined,
      dataType,
      columnType,
      generated: undefined
    };
  }
  $type() {
    return this;
  }
  notNull() {
    this.config.notNull = true;
    return this;
  }
  default(value3) {
    this.config.default = value3;
    this.config.hasDefault = true;
    return this;
  }
  $defaultFn(fn3) {
    this.config.defaultFn = fn3;
    this.config.hasDefault = true;
    return this;
  }
  $default = this.$defaultFn;
  $onUpdateFn(fn3) {
    this.config.onUpdateFn = fn3;
    this.config.hasDefault = true;
    return this;
  }
  $onUpdate = this.$onUpdateFn;
  primaryKey() {
    this.config.primaryKey = true;
    this.config.notNull = true;
    return this;
  }
  setName(name, casingFn) {
    if (this.config.name !== "")
      return;
    this.config.name = casingFn(name);
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/common.js
var SQLiteColumnBuilder = class extends ColumnBuilder {
  static [entityKind] = "SQLiteColumnBuilder";
  foreignKeyConfigs = [];
  references(ref, actions = {}) {
    this.foreignKeyConfigs.push({
      ref,
      actions
    });
    return this;
  }
  unique(name) {
    this.config.isUnique = true;
    this.config.uniqueName = name;
    return this;
  }
  generatedAlwaysAs(as3, config) {
    this.config.generated = {
      as: as3,
      type: "always",
      mode: config?.mode ?? "virtual"
    };
    return this;
  }
  buildForeignKeys(column, table) {
    return this.foreignKeyConfigs.map(({ ref, actions }) => {
      return ((ref2, actions2) => {
        const builder = new ForeignKeyBuilder2(() => {
          const foreignColumn = ref2();
          return {
            columns: [column],
            foreignColumns: [foreignColumn]
          };
        });
        if (actions2.onUpdate)
          builder.onUpdate(actions2.onUpdate);
        if (actions2.onDelete)
          builder.onDelete(actions2.onDelete);
        return builder.build(table);
      })(ref, actions);
    });
  }
};
var SQLiteColumn = class extends Column {
  static [entityKind] = "SQLiteColumn";
  table;
  constructor(table, config) {
    super(table, config);
    this.table = table;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/blob.js
function hexToText(hexString) {
  let result3 = "";
  for (let i = 0;i < hexString.length; i += 2) {
    const hexPair = hexString.slice(i, i + 2);
    const decimalValue = Number.parseInt(hexPair, 16);
    result3 += String.fromCodePoint(decimalValue);
  }
  return result3;
}
var SQLiteBigIntBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteBigIntBuilder";
  constructor(name) {
    super(name, "bigint int64", "SQLiteBigInt");
  }
  build(table) {
    return new SQLiteBigInt(table, this.config);
  }
};
var SQLiteBigInt = class extends SQLiteColumn {
  static [entityKind] = "SQLiteBigInt";
  getSQLType() {
    return "blob";
  }
  mapFromDriverValue = (value3) => {
    if (typeof value3 === "string")
      return BigInt(hexToText(value3));
    if (typeof Buffer !== "undefined" && Buffer.from) {
      const buf = Buffer.isBuffer(value3) ? value3 : value3 instanceof ArrayBuffer ? Buffer.from(value3) : value3.buffer ? Buffer.from(value3.buffer, value3.byteOffset, value3.byteLength) : Buffer.from(value3);
      return BigInt(buf.toString("utf8"));
    }
    return BigInt(textDecoder.decode(value3));
  };
  mapToDriverValue = (value3) => {
    return Buffer.from(value3.toString());
  };
};
var SQLiteBlobJsonBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteBlobJsonBuilder";
  constructor(name) {
    super(name, "object json", "SQLiteBlobJson");
  }
  build(table) {
    return new SQLiteBlobJson(table, this.config);
  }
};
var SQLiteBlobJson = class extends SQLiteColumn {
  static [entityKind] = "SQLiteBlobJson";
  getSQLType() {
    return "blob";
  }
  mapFromDriverValue = (value3) => {
    if (typeof value3 === "string")
      return JSON.parse(hexToText(value3));
    if (typeof Buffer !== "undefined" && Buffer.from) {
      const buf = Buffer.isBuffer(value3) ? value3 : value3 instanceof ArrayBuffer ? Buffer.from(value3) : value3.buffer ? Buffer.from(value3.buffer, value3.byteOffset, value3.byteLength) : Buffer.from(value3);
      return JSON.parse(buf.toString("utf8"));
    }
    return JSON.parse(textDecoder.decode(value3));
  };
  mapToDriverValue = (value3) => {
    return Buffer.from(JSON.stringify(value3));
  };
};
var SQLiteBlobBufferBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteBlobBufferBuilder";
  constructor(name) {
    super(name, "object buffer", "SQLiteBlobBuffer");
  }
  build(table) {
    return new SQLiteBlobBuffer(table, this.config);
  }
};
var SQLiteBlobBuffer = class extends SQLiteColumn {
  static [entityKind] = "SQLiteBlobBuffer";
  mapFromDriverValue = (value3) => {
    if (Buffer.isBuffer(value3))
      return value3;
    if (typeof value3 === "string")
      return Buffer.from(value3, "hex");
    return Buffer.from(value3);
  };
  getSQLType() {
    return "blob";
  }
};
function blob(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (config?.mode === "json")
    return new SQLiteBlobJsonBuilder(name);
  if (config?.mode === "bigint")
    return new SQLiteBigIntBuilder(name);
  return new SQLiteBlobBufferBuilder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/custom.js
var SQLiteCustomColumnBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteCustomColumnBuilder";
  constructor(name, fieldConfig, customTypeParams) {
    super(name, "custom", "SQLiteCustomColumn");
    this.config.fieldConfig = fieldConfig;
    this.config.customTypeParams = customTypeParams;
  }
  build(table) {
    return new SQLiteCustomColumn(table, this.config);
  }
};
var SQLiteCustomColumn = class extends SQLiteColumn {
  static [entityKind] = "SQLiteCustomColumn";
  sqlName;
  mapTo;
  mapFrom;
  mapJson;
  forJsonSelect;
  constructor(table, config) {
    super(table, config);
    this.sqlName = config.customTypeParams.dataType(config.fieldConfig);
    this.mapTo = config.customTypeParams.toDriver;
    this.mapFrom = config.customTypeParams.fromDriver;
    this.mapJson = config.customTypeParams.fromJson;
    this.forJsonSelect = config.customTypeParams.forJsonSelect;
  }
  getSQLType() {
    return this.sqlName;
  }
  mapFromDriverValue = (value3) => {
    return typeof this.mapFrom === "function" ? this.mapFrom(value3) : value3;
  };
  mapFromJsonValue(value3) {
    return typeof this.mapJson === "function" ? this.mapJson(value3) : this.mapFromDriverValue(value3);
  }
  jsonSelectIdentifier(identifier2, sql2) {
    if (typeof this.forJsonSelect === "function")
      return this.forJsonSelect(identifier2, sql2);
    const rawType = this.getSQLType().toLowerCase();
    const parenPos = rawType.indexOf("(");
    switch (parenPos + 1 ? rawType.slice(0, parenPos) : rawType) {
      case "numeric":
      case "decimal":
      case "bigint":
        return sql2`cast(${identifier2} as text)`;
      case "blob":
        return sql2`hex(${identifier2})`;
      default:
        return identifier2;
    }
  }
  mapToDriverValue = (value3) => {
    return typeof this.mapTo === "function" ? this.mapTo(value3) : value3;
  };
};
function customType2(customTypeParams) {
  return (a, b) => {
    const { name, config } = getColumnNameAndConfig(a, b);
    return new SQLiteCustomColumnBuilder(name, config, customTypeParams);
  };
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/integer.js
var SQLiteBaseIntegerBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteBaseIntegerBuilder";
  constructor(name, dataType, columnType) {
    super(name, dataType, columnType);
    this.config.autoIncrement = false;
  }
  primaryKey(config) {
    if (config?.autoIncrement)
      this.config.autoIncrement = true;
    this.config.hasDefault = true;
    return super.primaryKey();
  }
};
var SQLiteBaseInteger = class extends SQLiteColumn {
  static [entityKind] = "SQLiteBaseInteger";
  autoIncrement = this.config.autoIncrement;
  getSQLType() {
    return "integer";
  }
};
var SQLiteIntegerBuilder = class extends SQLiteBaseIntegerBuilder {
  static [entityKind] = "SQLiteIntegerBuilder";
  constructor(name) {
    super(name, "number int53", "SQLiteInteger");
  }
  build(table) {
    return new SQLiteInteger(table, this.config);
  }
};
var SQLiteInteger = class extends SQLiteBaseInteger {
  static [entityKind] = "SQLiteInteger";
};
var SQLiteTimestampBuilder = class extends SQLiteBaseIntegerBuilder {
  static [entityKind] = "SQLiteTimestampBuilder";
  constructor(name, mode) {
    super(name, "object date", "SQLiteTimestamp");
    this.config.mode = mode;
  }
  defaultNow() {
    return this.default(sql`(cast((julianday('now') - 2440587.5)*86400000 as integer))`);
  }
  build(table) {
    return new SQLiteTimestamp(table, this.config);
  }
};
var SQLiteTimestamp = class extends SQLiteBaseInteger {
  static [entityKind] = "SQLiteTimestamp";
  mode = this.config.mode;
  mapFromDriverValue = (value3) => {
    if (typeof value3 === "string")
      return new Date(value3.replaceAll('"', ""));
    if (this.config.mode === "timestamp")
      return /* @__PURE__ */ new Date(value3 * 1000);
    return new Date(value3);
  };
  mapToDriverValue = (value3) => {
    if (typeof value3 === "number")
      return value3;
    const unix = value3.getTime();
    if (this.config.mode === "timestamp")
      return Math.floor(unix / 1000);
    return unix;
  };
};
var SQLiteBooleanBuilder = class extends SQLiteBaseIntegerBuilder {
  static [entityKind] = "SQLiteBooleanBuilder";
  constructor(name, mode) {
    super(name, "boolean", "SQLiteBoolean");
    this.config.mode = mode;
  }
  build(table) {
    return new SQLiteBoolean(table, this.config);
  }
};
var SQLiteBoolean = class extends SQLiteBaseInteger {
  static [entityKind] = "SQLiteBoolean";
  mode = this.config.mode;
  mapFromDriverValue = (value3) => {
    return Number(value3) === 1;
  };
  mapToDriverValue = (value3) => {
    return value3 ? 1 : 0;
  };
};
function integer2(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (config?.mode === "timestamp" || config?.mode === "timestamp_ms")
    return new SQLiteTimestampBuilder(name, config.mode);
  if (config?.mode === "boolean")
    return new SQLiteBooleanBuilder(name, config.mode);
  return new SQLiteIntegerBuilder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/numeric.js
var SQLiteNumericBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteNumericBuilder";
  constructor(name) {
    super(name, "string numeric", "SQLiteNumeric");
  }
  build(table) {
    return new SQLiteNumeric(table, this.config);
  }
};
var SQLiteNumeric = class extends SQLiteColumn {
  static [entityKind] = "SQLiteNumeric";
  mapFromDriverValue = (value3) => {
    if (typeof value3 === "string")
      return value3;
    return String(value3);
  };
  getSQLType() {
    return "numeric";
  }
};
var SQLiteNumericNumberBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteNumericNumberBuilder";
  constructor(name) {
    super(name, "number", "SQLiteNumericNumber");
  }
  build(table) {
    return new SQLiteNumericNumber(table, this.config);
  }
};
var SQLiteNumericNumber = class extends SQLiteColumn {
  static [entityKind] = "SQLiteNumericNumber";
  mapFromDriverValue = (value3) => {
    if (typeof value3 === "number")
      return value3;
    return Number(value3);
  };
  mapToDriverValue = String;
  getSQLType() {
    return "numeric";
  }
};
var SQLiteNumericBigIntBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteNumericBigIntBuilder";
  constructor(name) {
    super(name, "bigint int64", "SQLiteNumericBigInt");
  }
  build(table) {
    return new SQLiteNumericBigInt(table, this.config);
  }
};
var SQLiteNumericBigInt = class extends SQLiteColumn {
  static [entityKind] = "SQLiteNumericBigInt";
  mapFromDriverValue = BigInt;
  mapToDriverValue = String;
  getSQLType() {
    return "numeric";
  }
};
function numeric2(a, b) {
  const { name, config } = getColumnNameAndConfig(a, b);
  const mode = config?.mode;
  return mode === "number" ? new SQLiteNumericNumberBuilder(name) : mode === "bigint" ? new SQLiteNumericBigIntBuilder(name) : new SQLiteNumericBuilder(name);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/real.js
var SQLiteRealBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteRealBuilder";
  constructor(name) {
    super(name, "number double", "SQLiteReal");
  }
  build(table) {
    return new SQLiteReal(table, this.config);
  }
};
var SQLiteReal = class extends SQLiteColumn {
  static [entityKind] = "SQLiteReal";
  getSQLType() {
    return "real";
  }
};
function real2(name) {
  return new SQLiteRealBuilder(name ?? "");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/text.js
var SQLiteTextBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteTextBuilder";
  constructor(name, config) {
    super(name, config.enum?.length ? "string enum" : "string", "SQLiteText");
    this.config.enumValues = config.enum;
    this.config.length = config.length;
  }
  build(table) {
    return new SQLiteText(table, this.config);
  }
};
var SQLiteText = class extends SQLiteColumn {
  static [entityKind] = "SQLiteText";
  enumValues = this.config.enumValues;
  constructor(table, config) {
    super(table, config);
  }
  getSQLType() {
    return `text${this.config.length ? `(${this.config.length})` : ""}`;
  }
};
var SQLiteTextJsonBuilder = class extends SQLiteColumnBuilder {
  static [entityKind] = "SQLiteTextJsonBuilder";
  constructor(name) {
    super(name, "object json", "SQLiteTextJson");
  }
  build(table) {
    return new SQLiteTextJson(table, this.config);
  }
};
var SQLiteTextJson = class extends SQLiteColumn {
  static [entityKind] = "SQLiteTextJson";
  getSQLType() {
    return "text";
  }
  mapFromDriverValue = (value3) => {
    return JSON.parse(value3);
  };
  mapToDriverValue = (value3) => {
    return JSON.stringify(value3);
  };
};
function text2(a, b = {}) {
  const { name, config } = getColumnNameAndConfig(a, b);
  if (config.mode === "json")
    return new SQLiteTextJsonBuilder(name);
  return new SQLiteTextBuilder(name, config);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/columns/all.js
function getSQLiteColumnBuilders() {
  return {
    blob,
    customType: customType2,
    integer: integer2,
    numeric: numeric2,
    real: real2,
    text: text2
  };
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/table.js
var InlineForeignKeys2 = Symbol.for("drizzle:SQLiteInlineForeignKeys");
var SQLiteTable = class extends Table {
  static [entityKind] = "SQLiteTable";
  static Symbol = Object.assign({}, Table.Symbol, { InlineForeignKeys: InlineForeignKeys2 });
  [Table.Symbol.Columns];
  [InlineForeignKeys2] = [];
  [Table.Symbol.ExtraConfigBuilder] = undefined;
};
function sqliteTableBase(name, columns, extraConfig, schema2, casing, baseName = name) {
  const casingFn = getCasingFn(casing);
  const rawTable = new SQLiteTable(name, schema2, baseName);
  const parsedColumns = typeof columns === "function" ? columns(getSQLiteColumnBuilders()) : columns;
  const builtColumns = Object.fromEntries(Object.entries(parsedColumns).map(([name2, colBuilderBase]) => {
    const colBuilder = colBuilderBase;
    colBuilder.setName(name2, casingFn);
    const column = colBuilder.build(rawTable).postBuild();
    rawTable[InlineForeignKeys2].push(...colBuilder.buildForeignKeys(column, rawTable));
    return [name2, column];
  }));
  const table = Object.assign(rawTable, builtColumns);
  table[Table.Symbol.Columns] = builtColumns;
  table[Table.Symbol.ExtraConfigColumns] = builtColumns;
  if (extraConfig)
    table[SQLiteTable.Symbol.ExtraConfigBuilder] = extraConfig;
  return table;
}
function sqliteTableWithCasing(casing) {
  return (name, columns, extraConfig) => sqliteTableBase(name, columns, extraConfig, undefined, casing);
}
var sqliteTable = sqliteTableWithCasing(undefined);

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/indexes.js
var IndexBuilderOn = class {
  static [entityKind] = "SQLiteIndexBuilderOn";
  constructor(name, unique) {
    this.name = name;
    this.unique = unique;
  }
  on(...columns) {
    return new IndexBuilder(this.name, columns, this.unique);
  }
};
var IndexBuilder = class {
  static [entityKind] = "SQLiteIndexBuilder";
  config;
  constructor(name, columns, unique) {
    this.config = {
      name,
      columns,
      unique,
      where: undefined
    };
  }
  where(condition) {
    this.config.where = condition;
    return this;
  }
  build(table) {
    return new Index(this.config, table);
  }
};
var Index = class {
  static [entityKind] = "SQLiteIndex";
  config;
  isNameExplicit;
  constructor(config, table) {
    this.config = {
      ...config,
      table
    };
    this.isNameExplicit = !!config.name;
  }
};
function index(name) {
  return new IndexBuilderOn(name, false);
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/utils.js
function extractUsedTable(table) {
  if (is2(table, SQLiteTable))
    return [`${table[Table.Symbol.BaseName]}`];
  if (is2(table, Subquery))
    return table._.usedTables ?? [];
  if (is2(table, SQL))
    return table.usedTables ?? [];
  return [];
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/query-builders/query-builder.js
var TypedQueryBuilder = class {
  static [entityKind] = "TypedQueryBuilder";
  getSelectedFields() {
    return this._.selectedFields;
  }
  withoutSelectionCastCodecs() {
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/select.js
var SQLiteSelectBuilder = class {
  static [entityKind] = "SQLiteSelectBuilder";
  fields;
  session;
  dialect;
  withList;
  distinct;
  constructor(config) {
    this.fields = config.fields;
    this.session = config.session;
    this.dialect = config.dialect;
    this.withList = config.withList;
    this.distinct = config.distinct;
  }
  from(source) {
    const isPartialSelect = !!this.fields;
    let fields;
    if (this.fields)
      fields = this.fields;
    else if (is2(source, Subquery))
      fields = Object.fromEntries(Object.keys(source._.selectedFields).map((key) => [key, source[key]]));
    else if (is2(source, SQLiteViewBase))
      fields = source[ViewBaseConfig].selectedFields;
    else if (is2(source, SQL))
      fields = {};
    else
      fields = getTableColumns(source);
    return new SQLiteSelectBase({
      table: source,
      fields,
      isPartialSelect,
      session: this.session,
      dialect: this.dialect,
      withList: this.withList,
      distinct: this.distinct
    });
  }
};
var SQLiteSelectQueryBuilderBase = class extends TypedQueryBuilder {
  static [entityKind] = "SQLiteSelectQueryBuilder";
  _;
  config;
  joinsNotNullableMap;
  tableName;
  isPartialSelect;
  session;
  dialect;
  cacheConfig = undefined;
  usedTables = /* @__PURE__ */ new Set;
  constructor({ table, fields, isPartialSelect, session, dialect, withList, distinct }) {
    super();
    this.config = {
      withList,
      table,
      fields: { ...fields },
      distinct,
      setOperators: []
    };
    this.isPartialSelect = isPartialSelect;
    this.session = session;
    this.dialect = dialect;
    this._ = {
      selectedFields: fields,
      config: this.config
    };
    this.tableName = getTableLikeName(table);
    this.joinsNotNullableMap = typeof this.tableName === "string" ? { [this.tableName]: true } : {};
    for (const item of extractUsedTable(table))
      this.usedTables.add(item);
  }
  getUsedTables() {
    return [...this.usedTables];
  }
  createJoin(joinType) {
    return (table, on) => {
      const baseTableName = this.tableName;
      const tableName = getTableLikeName(table);
      for (const item of extractUsedTable(table))
        this.usedTables.add(item);
      if (typeof tableName === "string" && this.config.joins?.some((join) => join.alias === tableName))
        throw new Error(`Alias "${tableName}" is already used in this query`);
      if (!this.isPartialSelect) {
        if (Object.keys(this.joinsNotNullableMap).length === 1 && typeof baseTableName === "string")
          this.config.fields = { [baseTableName]: this.config.fields };
        if (typeof tableName === "string" && !is2(table, SQL)) {
          const selection = is2(table, Subquery) ? table._.selectedFields : is2(table, View) ? table[ViewBaseConfig].selectedFields : table[Table.Symbol.Columns];
          this.config.fields[tableName] = selection;
        }
      }
      if (typeof on === "function")
        on = on(new Proxy(this.config.fields, new SelectionProxyHandler({
          sqlAliasedBehavior: "sql",
          sqlBehavior: "sql"
        })));
      if (!this.config.joins)
        this.config.joins = [];
      this.config.joins.push({
        on,
        table,
        joinType,
        alias: tableName
      });
      if (typeof tableName === "string")
        switch (joinType) {
          case "left":
            this.joinsNotNullableMap[tableName] = false;
            break;
          case "right":
            this.joinsNotNullableMap = Object.fromEntries(Object.entries(this.joinsNotNullableMap).map(([key]) => [key, false]));
            this.joinsNotNullableMap[tableName] = true;
            break;
          case "cross":
          case "inner":
            this.joinsNotNullableMap[tableName] = true;
            break;
          case "full":
            this.joinsNotNullableMap = Object.fromEntries(Object.entries(this.joinsNotNullableMap).map(([key]) => [key, false]));
            this.joinsNotNullableMap[tableName] = false;
            break;
        }
      return this;
    };
  }
  leftJoin = this.createJoin("left");
  rightJoin = this.createJoin("right");
  innerJoin = this.createJoin("inner");
  fullJoin = this.createJoin("full");
  crossJoin = this.createJoin("cross");
  createSetOperator(type, isAll) {
    return (rightSelection) => {
      const rightSelect = typeof rightSelection === "function" ? rightSelection(getSQLiteSetOperators()) : rightSelection;
      if (!haveSameKeys(this.getSelectedFields(), rightSelect.getSelectedFields()))
        throw new Error("Set operator error (union / intersect / except): selected fields are not the same or are in a different order");
      this.config.setOperators.push({
        type,
        isAll,
        rightSelect
      });
      return this;
    };
  }
  union = this.createSetOperator("union", false);
  unionAll = this.createSetOperator("union", true);
  intersect = this.createSetOperator("intersect", false);
  except = this.createSetOperator("except", false);
  addSetOperators(setOperators) {
    this.config.setOperators.push(...setOperators);
    return this;
  }
  where(where) {
    if (typeof where === "function")
      where = where(new Proxy(this.config.fields, new SelectionProxyHandler({
        sqlAliasedBehavior: "sql",
        sqlBehavior: "sql"
      })));
    this.config.where = where;
    return this;
  }
  having(having) {
    if (typeof having === "function")
      having = having(new Proxy(this.config.fields, new SelectionProxyHandler({
        sqlAliasedBehavior: "sql",
        sqlBehavior: "sql"
      })));
    this.config.having = having;
    return this;
  }
  groupBy(...columns) {
    if (typeof columns[0] === "function") {
      const groupBy2 = columns[0](new Proxy(this.config.fields, new SelectionProxyHandler({
        sqlAliasedBehavior: "alias",
        sqlBehavior: "sql"
      })));
      this.config.groupBy = Array.isArray(groupBy2) ? groupBy2 : [groupBy2];
    } else
      this.config.groupBy = columns;
    return this;
  }
  orderBy(...columns) {
    if (typeof columns[0] === "function") {
      const orderBy = columns[0](new Proxy(this.config.fields, new SelectionProxyHandler({
        sqlAliasedBehavior: "alias",
        sqlBehavior: "sql"
      })));
      const orderByArray = Array.isArray(orderBy) ? orderBy : [orderBy];
      if (this.config.setOperators.length > 0)
        this.config.setOperators.at(-1).orderBy = orderByArray;
      else
        this.config.orderBy = orderByArray;
    } else {
      const orderByArray = columns;
      if (this.config.setOperators.length > 0)
        this.config.setOperators.at(-1).orderBy = orderByArray;
      else
        this.config.orderBy = orderByArray;
    }
    return this;
  }
  limit(limit) {
    if (this.config.setOperators.length > 0)
      this.config.setOperators.at(-1).limit = limit;
    else
      this.config.limit = limit;
    return this;
  }
  offset(offset) {
    if (this.config.setOperators.length > 0)
      this.config.setOperators.at(-1).offset = offset;
    else
      this.config.offset = offset;
    return this;
  }
  getSQL() {
    return this.dialect.buildSelectQuery(this.config);
  }
  toSQL() {
    const { typings: _typings, ...rest } = this.dialect.sqlToQuery(this.getSQL());
    return rest;
  }
  as(alias) {
    const usedTables = [];
    usedTables.push(...extractUsedTable(this.config.table));
    if (this.config.joins)
      for (const it of this.config.joins)
        usedTables.push(...extractUsedTable(it.table));
    return new Proxy(new Subquery(this.getSQL(), this.config.fields, alias, false, [...new Set(usedTables)]), new SelectionProxyHandler({
      alias,
      sqlAliasedBehavior: "alias",
      sqlBehavior: "error"
    }));
  }
  getSelectedFields() {
    return new Proxy(this.config.fields, new SelectionProxyHandler({
      alias: this.tableName,
      sqlAliasedBehavior: "alias",
      sqlBehavior: "error"
    }));
  }
  withoutSelectionCastCodecs() {
    return this;
  }
  $dynamic() {
    return this;
  }
};
var SQLiteSelectBase = class extends SQLiteSelectQueryBuilderBase {
  static [entityKind] = "SQLiteSelect";
  _prepare(isOneTimeQuery = true) {
    if (!this.session)
      throw new Error("Cannot execute a query on a query builder. Please use a database instance instead.");
    const fieldsList = orderSelectedFields(this.config.fields);
    const query = this.session[isOneTimeQuery ? "prepareOneTimeQuery" : "prepareQuery"](this.dialect.sqlToQuery(this.getSQL()), fieldsList, "all", undefined, {
      type: "select",
      tables: [...this.usedTables]
    }, this.cacheConfig);
    query.joinsNotNullableMap = this.joinsNotNullableMap;
    return query;
  }
  $withCache(config) {
    this.cacheConfig = config === undefined ? {
      config: {},
      enabled: true,
      autoInvalidate: true
    } : config === false ? { enabled: false } : {
      enabled: true,
      autoInvalidate: true,
      ...config
    };
    return this;
  }
  prepare() {
    return this._prepare(false);
  }
  run = (placeholderValues) => {
    return this._prepare().run(placeholderValues);
  };
  all = (placeholderValues) => {
    return this._prepare().all(placeholderValues);
  };
  get = (placeholderValues) => {
    return this._prepare().get(placeholderValues);
  };
  values = (placeholderValues) => {
    return this._prepare().values(placeholderValues);
  };
  async execute() {
    return this.all();
  }
};
applyMixins(SQLiteSelectBase, [QueryPromise]);
function createSetOperator(type, isAll) {
  return (leftSelect, rightSelect, ...restSelects) => {
    const setOperators = [rightSelect, ...restSelects].map((select) => ({
      type,
      isAll,
      rightSelect: select
    }));
    for (const setOperator of setOperators)
      if (!haveSameKeys(leftSelect.getSelectedFields(), setOperator.rightSelect.getSelectedFields()))
        throw new Error("Set operator error (union / intersect / except): selected fields are not the same or are in a different order");
    return leftSelect.addSetOperators(setOperators);
  };
}
var getSQLiteSetOperators = () => ({
  union: union3,
  unionAll,
  intersect,
  except
});
var union3 = createSetOperator("union", false);
var unionAll = createSetOperator("union", true);
var intersect = createSetOperator("intersect", false);
var except = createSetOperator("except", false);

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/migrator.utils.js
function formatToMillis(dateStr) {
  const year = parseInt(dateStr.slice(0, 4), 10);
  const month = parseInt(dateStr.slice(4, 6), 10) - 1;
  const day = parseInt(dateStr.slice(6, 8), 10);
  const hour = parseInt(dateStr.slice(8, 10), 10);
  const minute = parseInt(dateStr.slice(10, 12), 10);
  const second = parseInt(dateStr.slice(12, 14), 10);
  return Date.UTC(year, month, day, hour, minute, second);
}
function getMigrationsToRun(params) {
  const { localMigrations, dbMigrations } = params;
  const dbNamesSet = new Set(dbMigrations.map((m) => m.name).filter((n) => n !== null));
  return localMigrations.filter((lm) => !lm.name || !dbNamesSet.has(lm.name));
}
// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/up-migrations/utils.js
var MIGRATIONS_TABLE_VERSIONS = {
  sqlite: 1,
  pg: 1,
  effect: 1,
  mysql: 1,
  mssql: 1,
  cockroach: 1,
  singlestore: 1
};
var GET_VERSION_FOR = {
  mysql: (columns) => {
    if (columns.includes("name"))
      return 1;
    return 0;
  },
  pg: (columns) => {
    if (columns.includes("name"))
      return 1;
    return 0;
  },
  effect: (columns) => {
    if (columns.includes("name"))
      return 1;
    return 0;
  },
  mssql: (columns) => {
    if (columns.includes("name"))
      return 1;
    return 0;
  },
  cockroach: (columns) => {
    if (columns.includes("name"))
      return 1;
    return 0;
  },
  singlestore: (columns) => {
    if (columns.includes("name"))
      return 1;
    return 0;
  },
  sqlite: (columns) => {
    if (columns.includes("name"))
      return 1;
    return 0;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/up-migrations/sqlite.js
function upgradeSyncIfNeeded(migrationsTable, session, localMigrations) {
  if (session.all(sql`SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ${migrationsTable}`).length === 0)
    return { newDb: true };
  const rows = session.all(sql`SELECT name as column_name FROM pragma_table_info(${migrationsTable})`);
  const version2 = GET_VERSION_FOR.sqlite(rows.map((r) => r.column_name));
  for (let v = version2;v < MIGRATIONS_TABLE_VERSIONS.sqlite; v++) {
    const upgradeFn = upgradeSyncFunctions[v];
    if (!upgradeFn)
      throw new Error(`No upgrade path from migration table version ${v} to ${v + 1}`);
    upgradeFn(migrationsTable, session, localMigrations);
  }
  return { newDb: false };
}
var upgradeSyncFunctions = { 0: (migrationsTable, session, localMigrations) => {
  const table = sql`${sql.identifier(migrationsTable)}`;
  const dbRows = session.all(sql`SELECT id, hash, created_at FROM ${table} ORDER BY id ASC`);
  localMigrations.sort((a, b) => a.folderMillis !== b.folderMillis ? a.folderMillis - b.folderMillis : (a.name ?? "").localeCompare(b.name ?? ""));
  const byMillis = /* @__PURE__ */ new Map;
  const byHash = /* @__PURE__ */ new Map;
  for (const lm of localMigrations) {
    if (!byMillis.has(lm.folderMillis))
      byMillis.set(lm.folderMillis, []);
    byMillis.get(lm.folderMillis).push(lm);
    byHash.set(lm.hash, lm);
  }
  const toApply = [];
  let unmatched = [];
  for (const dbRow of dbRows) {
    const stringified = String(dbRow.created_at);
    const millis2 = Number(stringified.substring(0, stringified.length - 3) + "000");
    const candidates = byMillis.get(millis2);
    let matched;
    let matchedBy = null;
    if (candidates && candidates.length === 1) {
      matched = candidates[0];
      matchedBy = "millis";
    } else if (candidates && candidates.length > 1) {
      matched = candidates.find((c) => c.hash && dbRow.hash && c.hash === dbRow.hash);
      if (matched)
        matchedBy = "hash";
    } else {
      matched = byHash.get(dbRow.hash);
      if (matched)
        matchedBy = "hash";
    }
    if (matched)
      toApply.push({
        id: dbRow.id,
        name: matched.name,
        hash: dbRow.hash,
        created_at: stringified,
        matchedBy: dbRow.id ? "id" : matchedBy
      });
    else
      unmatched.push(dbRow);
  }
  if (unmatched.length > 0)
    throw Error(`While upgrading your database migrations table we found ${unmatched.length} (${unmatched.map((it) => `[id: ${it.id}, created_at: ${it.created_at}]`).join(", ")}) migrations in the database that do not match any local migration. This means that some migrations were applied to the database but are missing from the local environment`);
  session.transaction((tx2) => {
    tx2.run(sql`ALTER TABLE ${table} ADD COLUMN ${sql.identifier("name")} text`);
    tx2.run(sql`ALTER TABLE ${table} ADD COLUMN ${sql.identifier("applied_at")} TEXT`);
    for (const backfillEntry of toApply) {
      const updateQuery = sql`UPDATE ${table} SET ${sql.identifier("name")} = ${backfillEntry.name}, ${sql.identifier("applied_at")} = NULL WHERE`;
      if (backfillEntry.id)
        updateQuery.append(sql` ${sql.identifier("id")} = ${backfillEntry.id}`);
      else if (backfillEntry.matchedBy === "millis")
        updateQuery.append(sql` ${sql.identifier("created_at")} = ${backfillEntry.created_at}`);
      else
        updateQuery.append(sql` ${sql.identifier("hash")} = ${backfillEntry.hash}`);
      tx2.run(updateQuery);
    }
  });
} };

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/dialect.js
var SQLiteDialect = class {
  static [entityKind] = "SQLiteDialect";
  constructor(_config) {}
  escapeName(name2) {
    return `"${name2.replace(/"/g, '""')}"`;
  }
  escapeParam(_num) {
    return "?";
  }
  escapeString(str) {
    return `'${str.replace(/'/g, "''")}'`;
  }
  buildWithCTE(queries) {
    if (!queries?.length)
      return;
    const withSqlChunks = [sql`with `];
    for (const [i, w] of queries.entries()) {
      withSqlChunks.push(sql`${sql.identifier(w._.alias)} as (${w._.sql})`);
      if (i < queries.length - 1)
        withSqlChunks.push(sql`, `);
    }
    withSqlChunks.push(sql` `);
    return sql.join(withSqlChunks);
  }
  buildDeleteQuery({ table, where, returning, withList, limit, orderBy }) {
    const withSql = this.buildWithCTE(withList);
    const returningSql = returning ? sql` returning ${this.buildSelection(returning, { isSingleTable: true })}` : undefined;
    return sql`${withSql}delete from ${table}${where ? sql` where ${where}` : undefined}${returningSql}${this.buildOrderBy(orderBy)}${this.buildLimit(limit)}`;
  }
  buildUpdateSet(table, set2) {
    const tableColumns = table[Table.Symbol.Columns];
    const columnNames = Object.keys(tableColumns).filter((colName) => set2[colName] !== undefined || tableColumns[colName]?.onUpdateFn !== undefined);
    const setLength = columnNames.length;
    return sql.join(columnNames.flatMap((colName, i) => {
      const col = tableColumns[colName];
      const onUpdateFnResult = col.onUpdateFn?.();
      const value3 = set2[colName] ?? (is2(onUpdateFnResult, SQL) ? onUpdateFnResult : sql.param(onUpdateFnResult, col));
      const res = sql`${sql.identifier(col.name)} = ${value3}`;
      if (i < setLength - 1)
        return [res, sql.raw(", ")];
      return [res];
    }));
  }
  buildUpdateQuery({ table, set: set2, where, returning, withList, joins, from, limit, orderBy }) {
    const withSql = this.buildWithCTE(withList);
    const setSql = this.buildUpdateSet(table, set2);
    const fromSql = from && sql.join([sql.raw(" from "), this.buildFromTable(from)]);
    const joinsSql = this.buildJoins(joins);
    const returningSql = returning ? sql` returning ${this.buildSelection(returning, { isSingleTable: true })}` : undefined;
    return sql`${withSql}update ${table} set ${setSql}${fromSql}${joinsSql}${where ? sql` where ${where}` : undefined}${returningSql}${this.buildOrderBy(orderBy)}${this.buildLimit(limit)}`;
  }
  buildSelection(fields, { isSingleTable = false } = {}) {
    const columnsLen = fields.length;
    const chunks = fields.flatMap(({ field }, i) => {
      const chunk = [];
      if (is2(field, SQL.Aliased) && field.isSelectionField) {
        if (!isSingleTable && field.origin !== undefined)
          chunk.push(sql.identifier(field.origin), sql.raw("."));
        chunk.push(sql.identifier(field.fieldAlias));
      } else if (is2(field, SQL.Aliased) || is2(field, SQL)) {
        const query = is2(field, SQL.Aliased) ? field.sql : field;
        if (isSingleTable) {
          const newSql = new SQL(query.queryChunks.map((c) => {
            if (is2(c, Column))
              return sql.identifier(c.name);
            return c;
          }));
          chunk.push(query.shouldInlineParams ? newSql.inlineParams() : newSql);
        } else
          chunk.push(query);
        if (is2(field, SQL.Aliased))
          chunk.push(sql` as ${sql.identifier(field.fieldAlias)}`);
      } else if (is2(field, Column))
        if (field.columnType === "SQLiteNumericBigInt")
          if (isSingleTable)
            chunk.push(field.isAlias ? sql`cast(${sql.identifier(getOriginalColumnFromAlias(field).name)} as text) as ${field}` : sql`cast(${sql.identifier(field.name)} as text)`);
          else
            chunk.push(field.isAlias ? sql`cast(${getOriginalColumnFromAlias(field)} as text) as ${field}` : sql`cast(${field} as text)`);
        else if (isSingleTable)
          chunk.push(field.isAlias ? sql`${sql.identifier(getOriginalColumnFromAlias(field).name)} as ${field}` : sql.identifier(field.name));
        else
          chunk.push(field.isAlias ? sql`${getOriginalColumnFromAlias(field)} as ${field}` : field);
      else if (is2(field, Subquery)) {
        const entries = Object.entries(field._.selectedFields);
        if (entries.length === 1) {
          const entry = entries[0][1];
          const fieldDecoder = is2(entry, SQL) ? entry.decoder : is2(entry, Column) ? { mapFromDriverValue: (v) => entry.mapFromDriverValue(v) } : entry.sql.decoder;
          if (fieldDecoder)
            field._.sql.decoder = fieldDecoder;
        }
        chunk.push(field);
      }
      if (i < columnsLen - 1)
        chunk.push(sql`, `);
      return chunk;
    });
    return sql.join(chunks);
  }
  buildJoins(joins) {
    if (!joins || joins.length === 0)
      return;
    const joinsArray = [];
    if (joins)
      for (const [index2, joinMeta] of joins.entries()) {
        if (index2 === 0)
          joinsArray.push(sql` `);
        const table = joinMeta.table;
        const onSql = joinMeta.on ? sql` on ${joinMeta.on}` : undefined;
        if (is2(table, SQLiteTable)) {
          const tableName = table[SQLiteTable.Symbol.Name];
          const tableSchema = table[SQLiteTable.Symbol.Schema];
          const origTableName = table[SQLiteTable.Symbol.OriginalName];
          const alias = tableName === origTableName ? undefined : joinMeta.alias;
          joinsArray.push(sql`${sql.raw(joinMeta.joinType)} join ${tableSchema ? sql`${sql.identifier(tableSchema)}.` : undefined}${sql.identifier(origTableName)}${alias && sql` ${sql.identifier(alias)}`}${onSql}`);
        } else
          joinsArray.push(sql`${sql.raw(joinMeta.joinType)} join ${table}${onSql}`);
        if (index2 < joins.length - 1)
          joinsArray.push(sql` `);
      }
    return sql.join(joinsArray);
  }
  buildLimit(limit) {
    return typeof limit === "object" || typeof limit === "number" && limit >= 0 ? sql` limit ${limit}` : undefined;
  }
  buildOrderBy(orderBy) {
    const orderByList = [];
    if (orderBy)
      for (const [index2, orderByValue] of orderBy.entries()) {
        orderByList.push(orderByValue);
        if (index2 < orderBy.length - 1)
          orderByList.push(sql`, `);
      }
    return orderByList.length > 0 ? sql` order by ${sql.join(orderByList)}` : undefined;
  }
  buildFromTable(table) {
    if (is2(table, Table) && table[Table.Symbol.IsAlias])
      return sql`${sql`${sql.identifier(table[Table.Symbol.Schema] ?? "")}.`.if(table[Table.Symbol.Schema])}${sql.identifier(table[Table.Symbol.OriginalName])} ${sql.identifier(table[Table.Symbol.Name])}`;
    if (is2(table, View) && table[ViewBaseConfig].isAlias) {
      let fullName = sql`${sql.identifier(table[ViewBaseConfig].originalName)}`;
      if (table[ViewBaseConfig].schema)
        fullName = sql`${sql.identifier(table[ViewBaseConfig].schema)}.${fullName}`;
      return sql`${fullName} ${sql.identifier(table[ViewBaseConfig].name)}`;
    }
    return table;
  }
  buildSelectQuery({ withList, fields, fieldsFlat, where, having, table, joins, orderBy, groupBy: groupBy2, limit, offset, distinct, setOperators }) {
    const fieldsList = fieldsFlat ?? orderSelectedFields(fields);
    for (const f of fieldsList)
      if (is2(f.field, Column) && getTableName(f.field.table) !== (is2(table, Subquery) ? table._.alias : is2(table, SQLiteViewBase) ? table[ViewBaseConfig].name : is2(table, SQL) ? undefined : getTableName(table)) && !((table2) => joins?.some(({ alias }) => alias === (table2[Table.Symbol.IsAlias] ? getTableName(table2) : table2[Table.Symbol.BaseName])))(f.field.table)) {
        const tableName = getTableName(f.field.table);
        throw new Error(`Your "${f.path.join("->")}" field references a column "${tableName}"."${f.field.name}", but the table "${tableName}" is not part of the query! Did you forget to join it?`);
      }
    const isSingleTable = !joins || joins.length === 0;
    const withSql = this.buildWithCTE(withList);
    const distinctSql = distinct ? sql` distinct` : undefined;
    const selection = this.buildSelection(fieldsList, { isSingleTable });
    const tableSql = this.buildFromTable(table);
    const joinsSql = this.buildJoins(joins);
    const whereSql = where ? sql` where ${where}` : undefined;
    const havingSql = having ? sql` having ${having}` : undefined;
    const groupByList = [];
    if (groupBy2)
      for (const [index2, groupByValue] of groupBy2.entries()) {
        groupByList.push(groupByValue);
        if (index2 < groupBy2.length - 1)
          groupByList.push(sql`, `);
      }
    const finalQuery = sql`${withSql}select${distinctSql} ${selection} from ${tableSql}${joinsSql}${whereSql}${groupByList.length > 0 ? sql` group by ${sql.join(groupByList)}` : undefined}${havingSql}${this.buildOrderBy(orderBy)}${this.buildLimit(limit)}${offset ? sql` offset ${offset}` : undefined}`;
    if (setOperators.length > 0)
      return this.buildSetOperations(finalQuery, setOperators);
    return finalQuery;
  }
  buildSetOperations(leftSelect, setOperators) {
    const [setOperator, ...rest] = setOperators;
    if (!setOperator)
      throw new Error("Cannot pass undefined values to any set operator");
    if (rest.length === 0)
      return this.buildSetOperationQuery({
        leftSelect,
        setOperator
      });
    return this.buildSetOperations(this.buildSetOperationQuery({
      leftSelect,
      setOperator
    }), rest);
  }
  buildSetOperationQuery({ leftSelect, setOperator: { type, isAll, rightSelect, limit, orderBy, offset } }) {
    const leftChunk = sql`${leftSelect.getSQL()} `;
    const rightChunk = sql`${rightSelect.getSQL()}`;
    let orderBySql;
    if (orderBy && orderBy.length > 0) {
      const orderByValues = [];
      for (const singleOrderBy of orderBy)
        if (is2(singleOrderBy, SQLiteColumn))
          orderByValues.push(sql.identifier(singleOrderBy.name));
        else if (is2(singleOrderBy, SQL)) {
          for (let i = 0;i < singleOrderBy.queryChunks.length; i++) {
            const chunk = singleOrderBy.queryChunks[i];
            if (is2(chunk, SQLiteColumn))
              singleOrderBy.queryChunks[i] = sql.identifier(chunk.name);
          }
          orderByValues.push(sql`${singleOrderBy}`);
        } else
          orderByValues.push(sql`${singleOrderBy}`);
      orderBySql = sql` order by ${sql.join(orderByValues, sql`, `)}`;
    }
    const limitSql = typeof limit === "object" || typeof limit === "number" && limit >= 0 ? sql` limit ${limit}` : undefined;
    const operatorChunk = sql.raw(`${type} ${isAll ? "all " : ""}`);
    const offsetSql = offset ? sql` offset ${offset}` : undefined;
    return sql`${leftChunk}${operatorChunk}${rightChunk}${orderBySql}${limitSql}${offsetSql}`;
  }
  buildInsertQuery({ table, values: valuesOrSelect, onConflict, returning, withList, select }) {
    const valuesSqlList = [];
    const columns = table[Table.Symbol.Columns];
    const colEntries = Object.entries(columns).filter(([_, col]) => !col.shouldDisableInsert());
    const insertOrder = colEntries.map(([, column]) => sql.identifier(column.name));
    if (select) {
      const select2 = valuesOrSelect;
      if (is2(select2, SQL))
        valuesSqlList.push(select2);
      else
        valuesSqlList.push(select2.getSQL());
    } else {
      const values = valuesOrSelect;
      valuesSqlList.push(sql.raw("values "));
      for (const [valueIndex, value3] of values.entries()) {
        const valueList = [];
        for (const [fieldName, col] of colEntries) {
          const colValue = value3[fieldName];
          if (colValue === undefined || is2(colValue, Param) && colValue.value === undefined) {
            let defaultValue;
            if (col.default !== null && col.default !== undefined)
              defaultValue = is2(col.default, SQL) ? col.default : sql.param(col.default, col);
            else if (col.defaultFn !== undefined) {
              const defaultFnResult = col.defaultFn();
              defaultValue = is2(defaultFnResult, SQL) ? defaultFnResult : sql.param(defaultFnResult, col);
            } else if (!col.default && col.onUpdateFn !== undefined) {
              const onUpdateFnResult = col.onUpdateFn();
              defaultValue = is2(onUpdateFnResult, SQL) ? onUpdateFnResult : sql.param(onUpdateFnResult, col);
            } else
              defaultValue = sql`null`;
            valueList.push(defaultValue);
          } else
            valueList.push(colValue);
        }
        valuesSqlList.push(valueList);
        if (valueIndex < values.length - 1)
          valuesSqlList.push(sql`, `);
      }
    }
    const withSql = this.buildWithCTE(withList);
    const valuesSql = sql.join(valuesSqlList);
    const returningSql = returning ? sql` returning ${this.buildSelection(returning, { isSingleTable: true })}` : undefined;
    return sql`${withSql}insert into ${table} ${insertOrder} ${valuesSql}${onConflict?.length ? sql.join(onConflict) : undefined}${returningSql}`;
  }
  sqlToQuery(sql2, invokeSource) {
    return sql2.toQuery({
      escapeName: this.escapeName,
      escapeParam: this.escapeParam,
      escapeString: this.escapeString,
      invokeSource
    });
  }
  _buildRelationalQuery({ fullSchema, schema: schema2, tableNamesMap, table, tableConfig, queryConfig: config, tableAlias, nestedQueryRelation, joinOn }) {
    let selection = [];
    let limit, offset, orderBy = [], where;
    const joins = [];
    if (config === true)
      selection = Object.entries(tableConfig.columns).map(([key, value3]) => ({
        dbKey: value3.name,
        tsKey: key,
        field: aliasedTableColumn(value3, tableAlias),
        relationTableTsKey: undefined,
        isJson: false,
        selection: []
      }));
    else {
      const aliasedColumns = Object.fromEntries(Object.entries(tableConfig.columns).map(([key, value3]) => [key, aliasedTableColumn(value3, tableAlias)]));
      if (config.where) {
        const whereSql = typeof config.where === "function" ? config.where(aliasedColumns, getOperators()) : config.where;
        where = whereSql && mapColumnsInSQLToAlias(whereSql, tableAlias);
      }
      const fieldsSelection = [];
      let selectedColumns = [];
      if (config.columns) {
        let isIncludeMode = false;
        for (const [field, value3] of Object.entries(config.columns)) {
          if (value3 === undefined)
            continue;
          if (field in tableConfig.columns) {
            if (!isIncludeMode && value3 === true)
              isIncludeMode = true;
            selectedColumns.push(field);
          }
        }
        if (selectedColumns.length > 0)
          selectedColumns = isIncludeMode ? selectedColumns.filter((c) => config.columns?.[c] === true) : Object.keys(tableConfig.columns).filter((key) => !selectedColumns.includes(key));
      } else
        selectedColumns = Object.keys(tableConfig.columns);
      for (const field of selectedColumns) {
        const column = tableConfig.columns[field];
        fieldsSelection.push({
          tsKey: field,
          value: column
        });
      }
      let selectedRelations = [];
      if (config.with)
        selectedRelations = Object.entries(config.with).filter((entry) => !!entry[1]).map(([tsKey, queryConfig]) => ({
          tsKey,
          queryConfig,
          relation: tableConfig.relations[tsKey]
        }));
      let extras;
      if (config.extras) {
        extras = typeof config.extras === "function" ? config.extras(aliasedColumns, { sql }) : config.extras;
        for (const [tsKey, value3] of Object.entries(extras))
          fieldsSelection.push({
            tsKey,
            value: mapColumnsInAliasedSQLToAlias(value3, tableAlias)
          });
      }
      for (const { tsKey, value: value3 } of fieldsSelection)
        selection.push({
          dbKey: is2(value3, SQL.Aliased) ? value3.fieldAlias : tableConfig.columns[tsKey].name,
          tsKey,
          field: is2(value3, Column) ? aliasedTableColumn(value3, tableAlias) : value3,
          relationTableTsKey: undefined,
          isJson: false,
          selection: []
        });
      let orderByOrig = typeof config.orderBy === "function" ? config.orderBy(aliasedColumns, getOrderByOperators()) : config.orderBy ?? [];
      if (!Array.isArray(orderByOrig))
        orderByOrig = [orderByOrig];
      orderBy = orderByOrig.map((orderByValue) => {
        if (is2(orderByValue, Column))
          return aliasedTableColumn(orderByValue, tableAlias);
        return mapColumnsInSQLToAlias(orderByValue, tableAlias);
      });
      limit = config.limit;
      offset = config.offset;
      for (const { tsKey: selectedRelationTsKey, queryConfig: selectedRelationConfigValue, relation } of selectedRelations) {
        const normalizedRelation = normalizeRelation(schema2, tableNamesMap, relation);
        const relationTableTsName = tableNamesMap[getTableUniqueName(relation.referencedTable)];
        const relationTableAlias = `${tableAlias}_${selectedRelationTsKey}`;
        const joinOn2 = and(...normalizedRelation.fields.map((field2, i) => eq(aliasedTableColumn(normalizedRelation.references[i], relationTableAlias), aliasedTableColumn(field2, tableAlias))));
        const builtRelation = this._buildRelationalQuery({
          fullSchema,
          schema: schema2,
          tableNamesMap,
          table: fullSchema[relationTableTsName],
          tableConfig: schema2[relationTableTsName],
          queryConfig: is2(relation, One2) ? selectedRelationConfigValue === true ? { limit: 1 } : {
            ...selectedRelationConfigValue,
            limit: 1
          } : selectedRelationConfigValue,
          tableAlias: relationTableAlias,
          joinOn: joinOn2,
          nestedQueryRelation: relation
        });
        const field = sql`(${builtRelation.sql})`.as(selectedRelationTsKey);
        selection.push({
          dbKey: selectedRelationTsKey,
          tsKey: selectedRelationTsKey,
          field,
          relationTableTsKey: relationTableTsName,
          isJson: true,
          selection: builtRelation.selection
        });
      }
    }
    if (selection.length === 0)
      throw new DrizzleError({ message: `No fields selected for table "${tableConfig.tsName}" ("${tableAlias}"). You need to have at least one item in "columns", "with" or "extras". If you need to select all columns, omit the "columns" key or set it to undefined.` });
    let result3;
    where = and(joinOn, where);
    if (nestedQueryRelation) {
      let field = sql`json_array(${sql.join(selection.map(({ field: field2 }) => is2(field2, SQLiteColumn) ? sql.identifier(field2.name) : is2(field2, SQL.Aliased) ? field2.sql : field2), sql`, `)})`;
      if (is2(nestedQueryRelation, Many))
        field = sql`coalesce(json_group_array(${field}), json_array())`;
      const nestedSelection = [{
        dbKey: "data",
        tsKey: "data",
        field: field.as("data"),
        isJson: true,
        relationTableTsKey: tableConfig.tsName,
        selection
      }];
      if (limit !== undefined || offset !== undefined || orderBy.length > 0) {
        result3 = this.buildSelectQuery({
          table: aliasedTable(table, tableAlias),
          fields: {},
          fieldsFlat: [{
            path: [],
            field: sql.raw("*")
          }],
          where,
          limit,
          offset,
          orderBy,
          setOperators: []
        });
        where = undefined;
        limit = undefined;
        offset = undefined;
        orderBy = undefined;
      } else
        result3 = aliasedTable(table, tableAlias);
      result3 = this.buildSelectQuery({
        table: is2(result3, SQLiteTable) ? result3 : new Subquery(result3, {}, tableAlias),
        fields: {},
        fieldsFlat: nestedSelection.map(({ field: field2 }) => ({
          path: [],
          field: is2(field2, Column) ? aliasedTableColumn(field2, tableAlias) : field2
        })),
        joins,
        where,
        limit,
        offset,
        orderBy,
        setOperators: []
      });
    } else
      result3 = this.buildSelectQuery({
        table: aliasedTable(table, tableAlias),
        fields: {},
        fieldsFlat: selection.map(({ field }) => ({
          path: [],
          field: is2(field, Column) ? aliasedTableColumn(field, tableAlias) : field
        })),
        joins,
        where,
        limit,
        offset,
        orderBy,
        setOperators: []
      });
    return {
      tableTsKey: tableConfig.tsName,
      sql: result3,
      selection
    };
  }
  nestedSelectionerror() {
    throw new DrizzleError({ message: `Views with nested selections are not supported by the relational query builder` });
  }
  buildRqbColumn(table, column, key) {
    if (is2(column, Column)) {
      const name2 = sql`${table}.${sql.identifier(column.name)}`;
      switch (column.columnType) {
        case "SQLiteBigInt":
        case "SQLiteBlobJson":
        case "SQLiteBlobBuffer":
          return sql`hex(${name2}) as ${sql.identifier(key)}`;
        case "SQLiteNumeric":
        case "SQLiteNumericNumber":
        case "SQLiteNumericBigInt":
          return sql`cast(${name2} as text) as ${sql.identifier(key)}`;
        case "SQLiteCustomColumn":
          return sql`${column.jsonSelectIdentifier(name2, sql)} as ${sql.identifier(key)}`;
        default:
          return sql`${name2} as ${sql.identifier(key)}`;
      }
    }
    return sql`${table}.${is2(column, SQL.Aliased) ? sql.identifier(column.fieldAlias) : isSQLWrapper(column) ? sql.identifier(key) : this.nestedSelectionerror()} as ${sql.identifier(key)}`;
  }
  unwrapAllColumns = (table, selection) => {
    return sql.join(Object.entries(table[TableColumns]).map(([k, v]) => {
      selection.push({
        key: k,
        field: v
      });
      return this.buildRqbColumn(table, v, k);
    }), sql`, `);
  };
  getSelectedTableColumns = (table, columns) => {
    const selectedColumns = [];
    const columnContainer = table[TableColumns];
    const entries = Object.entries(columns);
    let colSelectionMode;
    for (const [k, v] of entries) {
      if (v === undefined)
        continue;
      colSelectionMode = colSelectionMode || v;
      if (v) {
        const column = columnContainer[k];
        selectedColumns.push({
          column,
          tsName: k
        });
      }
    }
    if (colSelectionMode === false)
      for (const [k, v] of Object.entries(columnContainer)) {
        if (columns[k] === false)
          continue;
        selectedColumns.push({
          column: v,
          tsName: k
        });
      }
    return selectedColumns;
  };
  buildColumns = (table, selection, params) => params?.columns ? (() => {
    const columnIdentifiers = [];
    const selectedColumns = this.getSelectedTableColumns(table, params?.columns);
    for (const { column, tsName } of selectedColumns) {
      columnIdentifiers.push(this.buildRqbColumn(table, column, tsName));
      selection.push({
        key: tsName,
        field: column
      });
    }
    return columnIdentifiers.length ? sql.join(columnIdentifiers, sql`, `) : undefined;
  })() : this.unwrapAllColumns(table, selection);
  buildRelationalQuery({ schema: schema2, table, tableConfig, queryConfig: config, relationWhere, mode, isNested, errorPath, depth, throughJoin, jsonb: jsonb2 }) {
    const selection = [];
    const isSingle = mode === "first";
    const params = config === true ? undefined : config;
    const currentPath = errorPath ?? "";
    const currentDepth = depth ?? 0;
    if (!currentDepth)
      table = aliasedTable(table, `d${currentDepth}`);
    const limit = isSingle ? 1 : params?.limit;
    const offset = params?.offset;
    const columns = this.buildColumns(table, selection, params);
    const where = params?.where && relationWhere ? and(relationsFilterToSQL(table, params.where, tableConfig.relations, schema2), relationWhere) : params?.where ? relationsFilterToSQL(table, params.where, tableConfig.relations, schema2) : relationWhere;
    const order = params?.orderBy ? relationsOrderToSQL(table, params.orderBy) : undefined;
    const extras = params?.extras ? relationExtrasToSQL(table, params.extras) : undefined;
    if (extras)
      selection.push(...extras.selection);
    const joins = params ? (() => {
      const { with: joins2 } = params;
      if (!joins2)
        return;
      const withEntries = Object.entries(joins2).filter(([_, v]) => v);
      if (!withEntries.length)
        return;
      return sql.join(withEntries.map(([k, join]) => {
        const relation = tableConfig.relations[k];
        const isSingle2 = is2(relation, One);
        const targetTable = aliasedTable(relation.targetTable, `d${currentDepth + 1}`);
        const throughTable = relation.throughTable ? aliasedTable(relation.throughTable, `tr${currentDepth}`) : undefined;
        const { filter: filter6, joinCondition } = relationToSQL(relation, table, targetTable, throughTable);
        const throughJoin2 = throughTable ? sql` inner join ${getTableAsAliasSQL(throughTable)} on ${joinCondition}` : undefined;
        const innerQuery = this.buildRelationalQuery({
          table: targetTable,
          mode: isSingle2 ? "first" : "many",
          schema: schema2,
          queryConfig: join,
          tableConfig: schema2[relation.targetTableName],
          relationWhere: filter6,
          isNested: true,
          errorPath: `${currentPath.length ? `${currentPath}.` : ""}${k}`,
          depth: currentDepth + 1,
          throughJoin: throughJoin2,
          jsonb: jsonb2
        });
        selection.push({
          field: targetTable,
          key: k,
          selection: innerQuery.selection,
          isArray: !isSingle2,
          isOptional: (relation.optional ?? false) || join !== true && !!join.where
        });
        const jsonColumns = sql.join(innerQuery.selection.map((s) => {
          return sql`${sql.raw(this.escapeString(s.key))}, ${s.selection ? sql`${jsonb2}(${sql.identifier(s.key)})` : sql.identifier(s.key)}`;
        }), sql`, `);
        const json2 = isNested ? jsonb2 : sql`json`;
        return isSingle2 ? sql`(select ${json2}_object(${jsonColumns}) as ${sql.identifier("r")} from (${innerQuery.sql}) as ${sql.identifier("t")}) as ${sql.identifier(k)}` : sql`coalesce((select ${json2}_group_array(json_object(${jsonColumns})) as ${sql.identifier("r")} from (${innerQuery.sql}) as ${sql.identifier("t")}), ${jsonb2}_array()) as ${sql.identifier(k)}`;
      }), sql`, `);
    })() : undefined;
    const selectionArr = [
      columns,
      extras?.sql,
      joins
    ].filter((e) => e !== undefined);
    if (!selectionArr.length)
      throw new DrizzleError({ message: `No fields selected for table "${tableConfig.name}"${currentPath ? ` ("${currentPath}")` : ""}` });
    return {
      sql: sql`select ${sql.join(selectionArr, sql`, `)} from ${getTableAsAliasSQL(table)}${throughJoin}${sql` where ${where}`.if(where)}${sql` order by ${order}`.if(order)}${sql` limit ${limit}`.if(limit !== undefined)}${sql` offset ${offset}`.if(offset !== undefined)}`,
      selection
    };
  }
};
var SQLiteSyncDialect = class extends SQLiteDialect {
  static [entityKind] = "SQLiteSyncDialect";
  migrate(migrations, session, config) {
    const migrationsTable = config === undefined ? "__drizzle_migrations" : typeof config === "string" ? "__drizzle_migrations" : config.migrationsTable ?? "__drizzle_migrations";
    const { newDb } = upgradeSyncIfNeeded(migrationsTable, session, migrations);
    if (newDb) {
      const migrationTableCreate = sql`
			CREATE TABLE IF NOT EXISTS ${sql.identifier(migrationsTable)} (
				id INTEGER PRIMARY KEY,
				hash text NOT NULL,
				created_at numeric,
				name text,
				applied_at TEXT
			)`;
      session.run(migrationTableCreate);
    }
    const dbMigrations = session.all(sql`SELECT id, hash, created_at, name FROM ${sql.identifier(migrationsTable)}`);
    if (typeof config === "object" && config.init) {
      if (dbMigrations.length)
        return { exitCode: "databaseMigrations" };
      if (migrations.length > 1)
        return { exitCode: "localMigrations" };
      const [migration] = migrations;
      if (!migration)
        return;
      session.run(sql`insert into ${sql.identifier(migrationsTable)} ("hash", "created_at", "name", "applied_at") values(${migration.hash}, ${migration.folderMillis}, ${migration.name}, ${(/* @__PURE__ */ new Date()).toISOString()})`);
      return;
    }
    const migrationsToRun = getMigrationsToRun({
      localMigrations: migrations,
      dbMigrations
    });
    session.run(sql`BEGIN`);
    try {
      for (const migration of migrationsToRun) {
        for (const stmt of migration.sql)
          session.run(sql.raw(stmt));
        session.run(sql`INSERT INTO ${sql.identifier(migrationsTable)} ("hash", "created_at", "name", "applied_at") values(${migration.hash}, ${migration.folderMillis}, ${migration.name}, ${(/* @__PURE__ */ new Date()).toISOString()})`);
      }
      session.run(sql`COMMIT`);
    } catch (e) {
      session.run(sql`ROLLBACK`);
      throw e;
    }
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/query-builder.js
var QueryBuilder = class {
  static [entityKind] = "SQLiteQueryBuilder";
  dialect;
  dialectConfig;
  constructor(dialect) {
    this.dialect = is2(dialect, SQLiteDialect) ? dialect : undefined;
    this.dialectConfig = is2(dialect, SQLiteDialect) ? undefined : dialect;
  }
  $with = (alias, selection) => {
    const queryBuilder = this;
    const as3 = (qb) => {
      if (typeof qb === "function")
        qb = qb(queryBuilder);
      return new Proxy(new WithSubquery(qb.getSQL(), selection ?? ("getSelectedFields" in qb ? qb.getSelectedFields() ?? {} : {}), alias, true), new SelectionProxyHandler({
        alias,
        sqlAliasedBehavior: "alias",
        sqlBehavior: "error"
      }));
    };
    return { as: as3 };
  };
  with(...queries) {
    const self = this;
    function select(fields) {
      return new SQLiteSelectBuilder({
        fields: fields ?? undefined,
        session: undefined,
        dialect: self.getDialect(),
        withList: queries
      });
    }
    function selectDistinct(fields) {
      return new SQLiteSelectBuilder({
        fields: fields ?? undefined,
        session: undefined,
        dialect: self.getDialect(),
        withList: queries,
        distinct: true
      });
    }
    return {
      select,
      selectDistinct
    };
  }
  select(fields) {
    return new SQLiteSelectBuilder({
      fields: fields ?? undefined,
      session: undefined,
      dialect: this.getDialect()
    });
  }
  selectDistinct(fields) {
    return new SQLiteSelectBuilder({
      fields: fields ?? undefined,
      session: undefined,
      dialect: this.getDialect(),
      distinct: true
    });
  }
  getDialect() {
    if (!this.dialect)
      this.dialect = new SQLiteSyncDialect(this.dialectConfig);
    return this.dialect;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/delete.js
var SQLiteDeleteBase = class extends QueryPromise {
  static [entityKind] = "SQLiteDelete";
  config;
  constructor(table, session, dialect, withList) {
    super();
    this.table = table;
    this.session = session;
    this.dialect = dialect;
    this.config = {
      table,
      withList
    };
  }
  where(where) {
    this.config.where = where;
    return this;
  }
  orderBy(...columns) {
    if (typeof columns[0] === "function") {
      const orderBy = columns[0](new Proxy(this.config.table[Table.Symbol.Columns], new SelectionProxyHandler({
        sqlAliasedBehavior: "alias",
        sqlBehavior: "sql"
      })));
      const orderByArray = Array.isArray(orderBy) ? orderBy : [orderBy];
      this.config.orderBy = orderByArray;
    } else {
      const orderByArray = columns;
      this.config.orderBy = orderByArray;
    }
    return this;
  }
  limit(limit) {
    this.config.limit = limit;
    return this;
  }
  returning(fields = this.table[SQLiteTable.Symbol.Columns]) {
    this.config.returning = orderSelectedFields(fields);
    return this;
  }
  getSQL() {
    return this.dialect.buildDeleteQuery(this.config);
  }
  toSQL() {
    const { typings: _typings, ...rest } = this.dialect.sqlToQuery(this.getSQL());
    return rest;
  }
  _prepare(isOneTimeQuery = true) {
    return this.session[isOneTimeQuery ? "prepareOneTimeQuery" : "prepareQuery"](this.dialect.sqlToQuery(this.getSQL()), this.config.returning, this.config.returning ? "all" : "run", undefined, {
      type: "delete",
      tables: extractUsedTable(this.config.table)
    });
  }
  prepare() {
    return this._prepare(false);
  }
  run = (placeholderValues) => {
    return this._prepare().run(placeholderValues);
  };
  all = (placeholderValues) => {
    return this._prepare().all(placeholderValues);
  };
  get = (placeholderValues) => {
    return this._prepare().get(placeholderValues);
  };
  values = (placeholderValues) => {
    return this._prepare().values(placeholderValues);
  };
  async execute(placeholderValues) {
    return this._prepare().execute(placeholderValues);
  }
  $dynamic() {
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/insert.js
var SQLiteInsertBuilder = class {
  static [entityKind] = "SQLiteInsertBuilder";
  constructor(table, session, dialect, withList) {
    this.table = table;
    this.session = session;
    this.dialect = dialect;
    this.withList = withList;
  }
  values(values) {
    values = Array.isArray(values) ? values : [values];
    if (values.length === 0)
      throw new Error("values() must be called with at least one value");
    const mappedValues = values.map((entry) => {
      const result3 = {};
      const cols = this.table[Table.Symbol.Columns];
      for (const colKey of Object.keys(entry)) {
        const colValue = entry[colKey];
        result3[colKey] = is2(colValue, SQL) ? colValue : new Param(colValue, cols[colKey]);
      }
      return result3;
    });
    return new SQLiteInsertBase(this.table, mappedValues, this.session, this.dialect, this.withList);
  }
  select(selectQuery) {
    const select = typeof selectQuery === "function" ? selectQuery(new QueryBuilder) : selectQuery;
    if (!is2(select, SQL) && !haveSameKeys(this.table[TableColumns], select._.selectedFields))
      throw new Error("Insert select error: selected fields are not the same or are in a different order compared to the table definition");
    return new SQLiteInsertBase(this.table, select, this.session, this.dialect, this.withList, true);
  }
};
var SQLiteInsertBase = class extends QueryPromise {
  static [entityKind] = "SQLiteInsert";
  config;
  constructor(table, values, session, dialect, withList, select) {
    super();
    this.session = session;
    this.dialect = dialect;
    this.config = {
      table,
      values,
      withList,
      select
    };
  }
  returning(fields = this.config.table[SQLiteTable.Symbol.Columns]) {
    this.config.returning = orderSelectedFields(fields);
    return this;
  }
  onConflictDoNothing(config = {}) {
    if (!this.config.onConflict)
      this.config.onConflict = [];
    if (config.target === undefined)
      this.config.onConflict.push(sql` on conflict do nothing`);
    else {
      const targetSql = Array.isArray(config.target) ? sql`${config.target}` : sql`${[config.target]}`;
      const whereSql = config.where ? sql` where ${config.where}` : sql``;
      this.config.onConflict.push(sql` on conflict ${targetSql} do nothing${whereSql}`);
    }
    return this;
  }
  onConflictDoUpdate(config) {
    if (config.where && (config.targetWhere || config.setWhere))
      throw new Error('You cannot use both "where" and "targetWhere"/"setWhere" at the same time - "where" is deprecated, use "targetWhere" or "setWhere" instead.');
    if (!this.config.onConflict)
      this.config.onConflict = [];
    const whereSql = config.where ? sql` where ${config.where}` : undefined;
    const targetWhereSql = config.targetWhere ? sql` where ${config.targetWhere}` : undefined;
    const setWhereSql = config.setWhere ? sql` where ${config.setWhere}` : undefined;
    const targetSql = Array.isArray(config.target) ? sql`${config.target}` : sql`${[config.target]}`;
    const setSql = this.dialect.buildUpdateSet(this.config.table, mapUpdateSet(this.config.table, config.set));
    this.config.onConflict.push(sql` on conflict ${targetSql}${targetWhereSql} do update set ${setSql}${whereSql}${setWhereSql}`);
    return this;
  }
  getSQL() {
    return this.dialect.buildInsertQuery(this.config);
  }
  toSQL() {
    const { typings: _typings, ...rest } = this.dialect.sqlToQuery(this.getSQL());
    return rest;
  }
  _prepare(isOneTimeQuery = true) {
    return this.session[isOneTimeQuery ? "prepareOneTimeQuery" : "prepareQuery"](this.dialect.sqlToQuery(this.getSQL()), this.config.returning, this.config.returning ? "all" : "run", undefined, {
      type: "insert",
      tables: extractUsedTable(this.config.table)
    });
  }
  prepare() {
    return this._prepare(false);
  }
  run = (placeholderValues) => {
    return this._prepare().run(placeholderValues);
  };
  all = (placeholderValues) => {
    return this._prepare().all(placeholderValues);
  };
  get = (placeholderValues) => {
    return this._prepare().get(placeholderValues);
  };
  values = (placeholderValues) => {
    return this._prepare().values(placeholderValues);
  };
  async execute() {
    return this.config.returning ? this.all() : this.run();
  }
  $dynamic() {
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/query-builders/update.js
var SQLiteUpdateBuilder = class {
  static [entityKind] = "SQLiteUpdateBuilder";
  constructor(table, session, dialect, withList) {
    this.table = table;
    this.session = session;
    this.dialect = dialect;
    this.withList = withList;
  }
  set(values) {
    return new SQLiteUpdateBase(this.table, mapUpdateSet(this.table, values), this.session, this.dialect, this.withList);
  }
};
var SQLiteUpdateBase = class extends QueryPromise {
  static [entityKind] = "SQLiteUpdate";
  config;
  constructor(table, set2, session, dialect, withList) {
    super();
    this.session = session;
    this.dialect = dialect;
    this.config = {
      set: set2,
      table,
      withList,
      joins: []
    };
  }
  from(source) {
    this.config.from = source;
    return this;
  }
  createJoin(joinType) {
    return (table, on) => {
      const tableName = getTableLikeName(table);
      if (typeof tableName === "string" && this.config.joins.some((join) => join.alias === tableName))
        throw new Error(`Alias "${tableName}" is already used in this query`);
      if (typeof on === "function") {
        const from = this.config.from ? is2(table, SQLiteTable) ? table[Table.Symbol.Columns] : is2(table, Subquery) ? table._.selectedFields : is2(table, SQLiteViewBase) ? table[ViewBaseConfig].selectedFields : undefined : undefined;
        on = on(new Proxy(this.config.table[Table.Symbol.Columns], new SelectionProxyHandler({
          sqlAliasedBehavior: "sql",
          sqlBehavior: "sql"
        })), from && new Proxy(from, new SelectionProxyHandler({
          sqlAliasedBehavior: "sql",
          sqlBehavior: "sql"
        })));
      }
      this.config.joins.push({
        on,
        table,
        joinType,
        alias: tableName
      });
      return this;
    };
  }
  leftJoin = this.createJoin("left");
  rightJoin = this.createJoin("right");
  innerJoin = this.createJoin("inner");
  fullJoin = this.createJoin("full");
  where(where) {
    this.config.where = where;
    return this;
  }
  orderBy(...columns) {
    if (typeof columns[0] === "function") {
      const orderBy = columns[0](new Proxy(this.config.table[Table.Symbol.Columns], new SelectionProxyHandler({
        sqlAliasedBehavior: "alias",
        sqlBehavior: "sql"
      })));
      const orderByArray = Array.isArray(orderBy) ? orderBy : [orderBy];
      this.config.orderBy = orderByArray;
    } else {
      const orderByArray = columns;
      this.config.orderBy = orderByArray;
    }
    return this;
  }
  limit(limit) {
    this.config.limit = limit;
    return this;
  }
  returning(fields = this.config.table[SQLiteTable.Symbol.Columns]) {
    this.config.returning = orderSelectedFields(fields);
    return this;
  }
  getSQL() {
    return this.dialect.buildUpdateQuery(this.config);
  }
  toSQL() {
    const { typings: _typings, ...rest } = this.dialect.sqlToQuery(this.getSQL());
    return rest;
  }
  _prepare(isOneTimeQuery = true) {
    return this.session[isOneTimeQuery ? "prepareOneTimeQuery" : "prepareQuery"](this.dialect.sqlToQuery(this.getSQL()), this.config.returning, this.config.returning ? "all" : "run", undefined, {
      type: "insert",
      tables: extractUsedTable(this.config.table)
    });
  }
  prepare() {
    return this._prepare(false);
  }
  run = (placeholderValues) => {
    return this._prepare().run(placeholderValues);
  };
  all = (placeholderValues) => {
    return this._prepare().all(placeholderValues);
  };
  get = (placeholderValues) => {
    return this._prepare().get(placeholderValues);
  };
  values = (placeholderValues) => {
    return this._prepare().values(placeholderValues);
  };
  async execute() {
    return this.config.returning ? this.all() : this.run();
  }
  $dynamic() {
    return this;
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/db.js
var BaseSQLiteDatabase = class {
  static [entityKind] = "BaseSQLiteDatabase";
  _query;
  query;
  constructor(resultKind, dialect, session, relations, _schema, rowModeRQB, forbidJsonb) {
    this.resultKind = resultKind;
    this.dialect = dialect;
    this.session = session;
    this.rowModeRQB = rowModeRQB;
    this.forbidJsonb = forbidJsonb;
    this._ = _schema ? {
      schema: _schema.schema,
      fullSchema: _schema.fullSchema,
      tableNamesMap: _schema.tableNamesMap,
      relations
    } : {
      schema: undefined,
      fullSchema: {},
      tableNamesMap: {},
      relations
    };
    this._query = {};
    const query = this._query;
    if (this._.schema)
      for (const [tableName, columns] of Object.entries(this._.schema))
        query[tableName] = new _RelationalQueryBuilder(resultKind, _schema.fullSchema, this._.schema, this._.tableNamesMap, _schema.fullSchema[tableName], columns, dialect, session);
    this.query = {};
    for (const [tableName, relation] of Object.entries(relations))
      this.query[tableName] = new RelationalQueryBuilder(resultKind, relations, relations[relation.name].table, relation, dialect, session, rowModeRQB, forbidJsonb);
    this.$cache = { invalidate: async (_params) => {} };
  }
  $with = (alias, selection) => {
    const self = this;
    const as3 = (qb) => {
      if (typeof qb === "function")
        qb = qb(new QueryBuilder(self.dialect));
      return new Proxy(new WithSubquery(qb.getSQL(), selection ?? ("getSelectedFields" in qb ? qb.getSelectedFields() ?? {} : {}), alias, true), new SelectionProxyHandler({
        alias,
        sqlAliasedBehavior: "alias",
        sqlBehavior: "error"
      }));
    };
    return { as: as3 };
  };
  $count(source, filters) {
    return new SQLiteCountBuilder({
      source,
      filters,
      session: this.session
    });
  }
  with(...queries) {
    const self = this;
    function select(fields) {
      return new SQLiteSelectBuilder({
        fields: fields ?? undefined,
        session: self.session,
        dialect: self.dialect,
        withList: queries
      });
    }
    function selectDistinct(fields) {
      return new SQLiteSelectBuilder({
        fields: fields ?? undefined,
        session: self.session,
        dialect: self.dialect,
        withList: queries,
        distinct: true
      });
    }
    function update2(table) {
      return new SQLiteUpdateBuilder(table, self.session, self.dialect, queries);
    }
    function insert(into) {
      return new SQLiteInsertBuilder(into, self.session, self.dialect, queries);
    }
    function delete_(from) {
      return new SQLiteDeleteBase(from, self.session, self.dialect, queries);
    }
    return {
      select,
      selectDistinct,
      update: update2,
      insert,
      delete: delete_
    };
  }
  select(fields) {
    return new SQLiteSelectBuilder({
      fields: fields ?? undefined,
      session: this.session,
      dialect: this.dialect
    });
  }
  selectDistinct(fields) {
    return new SQLiteSelectBuilder({
      fields: fields ?? undefined,
      session: this.session,
      dialect: this.dialect,
      distinct: true
    });
  }
  update(table) {
    return new SQLiteUpdateBuilder(table, this.session, this.dialect);
  }
  $cache;
  insert(into) {
    return new SQLiteInsertBuilder(into, this.session, this.dialect);
  }
  delete(from) {
    return new SQLiteDeleteBase(from, this.session, this.dialect);
  }
  run(query) {
    const sequel = typeof query === "string" ? sql.raw(query) : query.getSQL();
    if (this.resultKind === "async")
      return new SQLiteRaw(async () => this.session.run(sequel), () => sequel, "run", this.dialect, this.session.extractRawRunValueFromBatchResult.bind(this.session));
    return this.session.run(sequel);
  }
  all(query) {
    const sequel = typeof query === "string" ? sql.raw(query) : query.getSQL();
    if (this.resultKind === "async")
      return new SQLiteRaw(async () => this.session.all(sequel), () => sequel, "all", this.dialect, this.session.extractRawAllValueFromBatchResult.bind(this.session));
    return this.session.all(sequel);
  }
  get(query) {
    const sequel = typeof query === "string" ? sql.raw(query) : query.getSQL();
    if (this.resultKind === "async")
      return new SQLiteRaw(async () => this.session.get(sequel), () => sequel, "get", this.dialect, this.session.extractRawGetValueFromBatchResult.bind(this.session));
    return this.session.get(sequel);
  }
  values(query) {
    const sequel = typeof query === "string" ? sql.raw(query) : query.getSQL();
    if (this.resultKind === "async")
      return new SQLiteRaw(async () => this.session.values(sequel), () => sequel, "values", this.dialect, this.session.extractRawValuesValueFromBatchResult.bind(this.session));
    return this.session.values(sequel);
  }
  transaction(transaction, config) {
    return this.session.transaction(transaction, config);
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/cache/core/cache.js
var Cache = class {
  static [entityKind] = "Cache";
};
var NoopCache = class extends Cache {
  static [entityKind] = "NoopCache";
  strategy() {
    return "all";
  }
  async get(_key) {}
  async put(_hashedQuery, _response, _tables, _config) {}
  async onMutate(_params) {}
};
async function hashQuery(sql2, params) {
  const dataToHash = `${sql2}-${JSON.stringify(params, (_, v) => typeof v === "bigint" ? `${v}n` : v)}`;
  const data = new TextEncoder().encode(dataToHash);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(hashBuffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/sqlite-core/session.js
var ExecuteResultSync = class extends QueryPromise {
  static [entityKind] = "ExecuteResultSync";
  constructor(resultCb) {
    super();
    this.resultCb = resultCb;
  }
  async execute() {
    return this.resultCb();
  }
  sync() {
    return this.resultCb();
  }
};
var SQLitePreparedQuery = class {
  static [entityKind] = "PreparedQuery";
  joinsNotNullableMap;
  constructor(mode, executeMethod, query, cache, queryMetadata, cacheConfig) {
    this.mode = mode;
    this.executeMethod = executeMethod;
    this.query = query;
    this.cache = cache;
    this.queryMetadata = queryMetadata;
    this.cacheConfig = cacheConfig;
    if (cache && cache.strategy() === "all" && cacheConfig === undefined)
      this.cacheConfig = {
        enabled: true,
        autoInvalidate: true
      };
    if (!this.cacheConfig?.enabled)
      this.cacheConfig = undefined;
  }
  async queryWithCache(queryString, params, query) {
    if (this.cache === undefined || is2(this.cache, NoopCache) || this.queryMetadata === undefined)
      try {
        return await query();
      } catch (e) {
        throw new DrizzleQueryError(queryString, params, e);
      }
    if (this.cacheConfig && !this.cacheConfig.enabled)
      try {
        return await query();
      } catch (e) {
        throw new DrizzleQueryError(queryString, params, e);
      }
    if ((this.queryMetadata.type === "insert" || this.queryMetadata.type === "update" || this.queryMetadata.type === "delete") && this.queryMetadata.tables.length > 0)
      try {
        const [res] = await Promise.all([query(), this.cache.onMutate({ tables: this.queryMetadata.tables })]);
        return res;
      } catch (e) {
        throw new DrizzleQueryError(queryString, params, e);
      }
    if (!this.cacheConfig)
      try {
        return await query();
      } catch (e) {
        throw new DrizzleQueryError(queryString, params, e);
      }
    if (this.queryMetadata.type === "select") {
      const fromCache = await this.cache.get(this.cacheConfig.tag ?? await hashQuery(queryString, params), this.queryMetadata.tables, this.cacheConfig.tag !== undefined, this.cacheConfig.autoInvalidate);
      if (fromCache === undefined) {
        let result3;
        try {
          result3 = await query();
        } catch (e) {
          throw new DrizzleQueryError(queryString, params, e);
        }
        await this.cache.put(this.cacheConfig.tag ?? await hashQuery(queryString, params), result3, this.cacheConfig.autoInvalidate ? this.queryMetadata.tables : [], this.cacheConfig.tag !== undefined, this.cacheConfig.config);
        return result3;
      }
      return fromCache;
    }
    try {
      return await query();
    } catch (e) {
      throw new DrizzleQueryError(queryString, params, e);
    }
  }
  getQuery() {
    return this.query;
  }
  mapRunResult(result3, _isFromBatch) {
    return result3;
  }
  mapAllResult(_result, _isFromBatch) {
    throw new Error("Not implemented");
  }
  mapGetResult(_result, _isFromBatch) {
    throw new Error("Not implemented");
  }
  execute(placeholderValues) {
    if (this.mode === "async")
      return this[this.executeMethod](placeholderValues);
    return new ExecuteResultSync(() => this[this.executeMethod](placeholderValues));
  }
  mapResult(response, isFromBatch) {
    switch (this.executeMethod) {
      case "run":
        return this.mapRunResult(response, isFromBatch);
      case "all":
        return this.mapAllResult(response, isFromBatch);
      case "get":
        return this.mapGetResult(response, isFromBatch);
    }
  }
};
var SQLiteSession = class {
  static [entityKind] = "SQLiteSession";
  constructor(dialect) {
    this.dialect = dialect;
  }
  prepareOneTimeQuery(query, fields, executeMethod, customResultMapper, queryMetadata, cacheConfig) {
    return this.prepareQuery(query, fields, executeMethod, customResultMapper, queryMetadata, cacheConfig);
  }
  prepareOneTimeRelationalQuery(query, fields, executeMethod, customResultMapper, config) {
    return this.prepareRelationalQuery(query, fields, executeMethod, customResultMapper, config);
  }
  run(query) {
    const staticQuery = this.dialect.sqlToQuery(query);
    try {
      return this.prepareOneTimeQuery(staticQuery, undefined, "run").run();
    } catch (err) {
      throw new DrizzleError({
        cause: err,
        message: `Failed to run the query '${staticQuery.sql}'`
      });
    }
  }
  extractRawRunValueFromBatchResult(result3) {
    return result3;
  }
  all(query) {
    return this.prepareOneTimeQuery(this.dialect.sqlToQuery(query), undefined, "run").all();
  }
  extractRawAllValueFromBatchResult(_result) {
    throw new Error("Not implemented");
  }
  get(query) {
    return this.prepareOneTimeQuery(this.dialect.sqlToQuery(query), undefined, "run").get();
  }
  extractRawGetValueFromBatchResult(_result) {
    throw new Error("Not implemented");
  }
  values(query) {
    return this.prepareOneTimeQuery(this.dialect.sqlToQuery(query), undefined, "run").values();
  }
  async count(sql2) {
    return (await this.values(sql2))[0][0];
  }
  extractRawValuesValueFromBatchResult(_result) {
    throw new Error("Not implemented");
  }
};
var SQLiteTransaction = class extends BaseSQLiteDatabase {
  static [entityKind] = "SQLiteTransaction";
  constructor(resultType, dialect, session, relations, schema2, nestedIndex = 0, rowModeRQB, forbidJsonb) {
    super(resultType, dialect, session, relations, schema2, rowModeRQB, forbidJsonb);
    this.relations = relations;
    this.schema = schema2;
    this.nestedIndex = nestedIndex;
  }
  rollback() {
    throw new TransactionRollbackError;
  }
};
// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/bun-sqlite/session.js
var SQLiteBunSession = class extends SQLiteSession {
  static [entityKind] = "SQLiteBunSession";
  logger;
  constructor(client, dialect, relations, schema2, options = {}) {
    super(dialect);
    this.client = client;
    this.relations = relations;
    this.schema = schema2;
    this.options = options;
    this.logger = options.logger ?? new NoopLogger;
  }
  exec(query) {
    this.client.exec(query);
  }
  prepareQuery(query, fields, executeMethod, customResultMapper) {
    return new PreparedQuery(this.client.prepare(query.sql), query, this.logger, fields, executeMethod, this.options.useJitMappers, customResultMapper);
  }
  prepareRelationalQuery(query, fields, executeMethod, customResultMapper, config) {
    return new PreparedQuery(this.client.prepare(query.sql), query, this.logger, fields, executeMethod, this.options.useJitMappers, customResultMapper, true, config);
  }
  transaction(transaction, config = {}) {
    const tx2 = new SQLiteBunTransaction("sync", this.dialect, this, this.relations, this.schema);
    let result3;
    this.client.transaction(() => {
      result3 = transaction(tx2);
    })[config.behavior ?? "deferred"]();
    return result3;
  }
};
var SQLiteBunTransaction = class SQLiteBunTransaction2 extends SQLiteTransaction {
  static [entityKind] = "SQLiteBunTransaction";
  transaction(transaction) {
    const savepointName = `sp${this.nestedIndex}`;
    const tx2 = new SQLiteBunTransaction2("sync", this.dialect, this.session, this.relations, this.schema, this.nestedIndex + 1);
    this.session.run(sql.raw(`savepoint ${savepointName}`));
    try {
      const result3 = transaction(tx2);
      this.session.run(sql.raw(`release savepoint ${savepointName}`));
      return result3;
    } catch (err) {
      this.session.run(sql.raw(`rollback to savepoint ${savepointName}`));
      throw err;
    }
  }
};
var PreparedQuery = class extends SQLitePreparedQuery {
  static [entityKind] = "SQLiteBunPreparedQuery";
  jitMapper;
  constructor(stmt, query, logger, fields, executeMethod, useJitMappers, customResultMapper, isRqbV2Query, rqbConfig) {
    super("sync", executeMethod, query);
    this.stmt = stmt;
    this.logger = logger;
    this.fields = fields;
    this.useJitMappers = useJitMappers;
    this.customResultMapper = customResultMapper;
    this.isRqbV2Query = isRqbV2Query;
    this.rqbConfig = rqbConfig;
  }
  run(placeholderValues) {
    const params = fillPlaceholders(this.query.params, placeholderValues ?? {});
    this.logger.logQuery(this.query.sql, params);
    return this.stmt.run(...params);
  }
  all(placeholderValues) {
    if (this.isRqbV2Query)
      return this.allRqbV2(placeholderValues);
    const { fields, query, logger, joinsNotNullableMap, stmt, customResultMapper } = this;
    if (!fields && !customResultMapper) {
      const params = fillPlaceholders(query.params, placeholderValues ?? {});
      logger.logQuery(query.sql, params);
      return stmt.all(...params);
    }
    const rows = this.values(placeholderValues);
    if (customResultMapper)
      return customResultMapper(rows);
    return this.useJitMappers ? (this.jitMapper = this.jitMapper ?? makeJitQueryMapper(fields, joinsNotNullableMap))(rows) : rows.map((row) => mapResultRow(fields, row, joinsNotNullableMap));
  }
  get(placeholderValues) {
    if (this.isRqbV2Query)
      return this.getRqbV2(placeholderValues);
    const params = fillPlaceholders(this.query.params, placeholderValues ?? {});
    this.logger.logQuery(this.query.sql, params);
    const { fields, joinsNotNullableMap, customResultMapper } = this;
    if (!fields && !customResultMapper) {
      const row2 = this.stmt.get(...params);
      if (!row2)
        return;
      return row2;
    }
    const row = this.stmt.values(...params)[0];
    if (!row)
      return;
    if (customResultMapper)
      return customResultMapper([row]);
    return this.useJitMappers ? (this.jitMapper = this.jitMapper ?? makeJitQueryMapper(fields, joinsNotNullableMap))([row])[0] : mapResultRow(fields, row, joinsNotNullableMap);
  }
  allRqbV2(placeholderValues) {
    const { query, logger, stmt, customResultMapper } = this;
    const params = fillPlaceholders(query.params, placeholderValues ?? {});
    logger.logQuery(query.sql, params);
    const rows = stmt.all(...params);
    return this.useJitMappers ? (this.jitMapper = this.jitMapper ?? makeJitRqbMapper(this.rqbConfig))(rows) : customResultMapper(rows);
  }
  getRqbV2(placeholderValues) {
    const params = fillPlaceholders(this.query.params, placeholderValues ?? {});
    this.logger.logQuery(this.query.sql, params);
    const { stmt, customResultMapper } = this;
    const row = stmt.get(...params);
    if (!row)
      return;
    return this.useJitMappers ? (this.jitMapper = this.jitMapper ?? makeJitRqbMapper(this.rqbConfig))([row]) : customResultMapper([row]);
  }
  values(placeholderValues) {
    const params = fillPlaceholders(this.query.params, placeholderValues ?? {});
    this.logger.logQuery(this.query.sql, params);
    return this.stmt.values(...params);
  }
};

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/bun-sqlite/driver.js
import { Database } from "bun:sqlite";
var SQLiteBunDatabase = class extends BaseSQLiteDatabase {
  static [entityKind] = "SQLiteBunDatabase";
};
function construct(client, config = {}) {
  const dialect = new SQLiteSyncDialect;
  let logger;
  if (config.logger === true)
    logger = new DefaultLogger;
  else if (config.logger !== false)
    logger = config.logger;
  let schema2;
  if (config.schema) {
    const tablesConfig = extractTablesRelationalConfig(config.schema, createTableRelationsHelpers);
    schema2 = {
      fullSchema: config.schema,
      schema: tablesConfig.tables,
      tableNamesMap: tablesConfig.tableNamesMap
    };
  }
  const relations = config.relations ?? {};
  const db = new SQLiteBunDatabase("sync", dialect, new SQLiteBunSession(client, dialect, relations, schema2, {
    logger,
    useJitMappers: jitCompatCheck(config.jit)
  }), relations, schema2);
  db.$client = client;
  return db;
}
function drizzle(...params) {
  if (params[0] === undefined || typeof params[0] === "string")
    return construct(params[0] === undefined ? new Database : new Database(params[0]), params[1]);
  const { connection, client, ...drizzleConfig } = params[0];
  if (client)
    return construct(client, drizzleConfig);
  if (typeof connection === "object") {
    const { source, ...opts } = connection;
    return construct(new Database(source, Object.values(opts).filter((v) => v !== undefined).length ? opts : undefined), drizzleConfig);
  }
  return construct(new Database(connection), drizzleConfig);
}
(function(_drizzle) {
  function mock2(config) {
    return construct({}, config);
  }
  _drizzle.mock = mock2;
})(drizzle || (drizzle = {}));
// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Config.js
var exports_Config = {};
__export(exports_Config, {
  withDefault: () => withDefault2,
  url: () => url,
  unwrap: () => unwrap2,
  succeed: () => succeed6,
  string: () => string3,
  schema: () => schema2,
  redacted: () => redacted,
  port: () => port,
  orElse: () => orElse,
  option: () => option3,
  number: () => number3,
  nonEmptyString: () => nonEmptyString,
  nested: () => nested2,
  mapOrFail: () => mapOrFail,
  map: () => map7,
  make: () => make12,
  logLevel: () => logLevel,
  literal: () => literal,
  isConfig: () => isConfig,
  int: () => int3,
  finite: () => finite,
  fail: () => fail7,
  duration: () => duration,
  date: () => date2,
  boolean: () => boolean3,
  all: () => all3,
  TrueValues: () => TrueValues,
  Record: () => Record2,
  Port: () => Port,
  LogLevel: () => LogLevel,
  FalseValues: () => FalseValues,
  Duration: () => Duration2,
  ConfigError: () => ConfigError,
  Boolean: () => Boolean3
});

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/ConfigProvider.js
function makeValue(value3) {
  return {
    _tag: "Value",
    value: value3
  };
}
function makeRecord(keys2, value3) {
  return {
    _tag: "Record",
    keys: keys2,
    value: value3
  };
}
function makeArray(length, value3) {
  return {
    _tag: "Array",
    length,
    value: value3
  };
}
var ConfigProvider = /* @__PURE__ */ Reference("effect/ConfigProvider", {
  defaultValue: () => fromEnv()
});
var Proto4 = {
  ...PipeInspectableProto,
  toJSON() {
    return {
      _id: "ConfigProvider"
    };
  }
};
function make11(get2, mapInput2, prefix) {
  const self = Object.create(Proto4);
  self.get = get2;
  self.mapInput = mapInput2;
  self.prefix = prefix;
  self.load = (path) => {
    if (mapInput2)
      path = mapInput2(path);
    if (prefix)
      path = [...prefix, ...path];
    return get2(path);
  };
  return self;
}
var nested = /* @__PURE__ */ dual(2, (self, prefix) => {
  const path = typeof prefix === "string" ? [prefix] : prefix;
  return make11(self.get, self.mapInput, self.prefix ? [...self.prefix, ...path] : path);
});
function fromEnv(options) {
  const env = options?.env ?? {
    ...globalThis?.process?.env,
    ...import.meta?.env
  };
  const trie = buildEnvTrie(env);
  return make11((path) => succeed5(nodeAtEnv(trie, env, path)));
}
function buildEnvTrie(env) {
  const root = {};
  for (const [name2, value3] of Object.entries(env)) {
    if (value3 === undefined)
      continue;
    const segments = name2.split("_");
    let node = root;
    for (const seg of segments) {
      node.children ??= {};
      node = node.children[seg] ??= {};
    }
    node.value = value3;
  }
  return root;
}
var NUMERIC_INDEX = /^(0|[1-9][0-9]*)$/;
function nodeAtEnv(trie, env, path) {
  const key = path.map(String).join("_");
  const leafValue = env[key];
  const trieNode = trieNodeAt(trie, path);
  const children = trieNode?.children ? Object.keys(trieNode.children) : [];
  if (children.length === 0) {
    return leafValue === undefined ? undefined : makeValue(leafValue);
  }
  const allNumeric = children.every((k) => NUMERIC_INDEX.test(k));
  if (allNumeric) {
    const length = Math.max(...children.map((k) => parseInt(k, 10))) + 1;
    return makeArray(length, leafValue);
  }
  return makeRecord(new Set(children), leafValue);
}
function trieNodeAt(root, path) {
  if (path.length === 0)
    return root;
  let node = root;
  for (const seg of path) {
    node = node?.children?.[String(seg)];
    if (!node)
      return;
  }
  return node;
}

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/LogLevel.js
var values = ["All", "Fatal", "Error", "Warn", "Info", "Debug", "Trace", "None"];

// ../../node_modules/.bun/effect@4.0.0-beta.59/node_modules/effect/dist/Config.js
var TypeId17 = "~effect/Config";
var isConfig = (u) => hasProperty(u, TypeId17);

class ConfigError {
  _tag = "ConfigError";
  name = "ConfigError";
  cause;
  constructor(cause) {
    this.cause = cause;
  }
  get message() {
    return this.cause.toString();
  }
  toString() {
    return `ConfigError(${this.message})`;
  }
}
var Proto5 = {
  ...PipeInspectableProto,
  ...YieldableProto,
  [TypeId17]: TypeId17,
  asEffect() {
    return flatMap3(ConfigProvider.asEffect(), (provider) => this.parse(provider));
  },
  toJSON() {
    return {
      _id: "Config"
    };
  }
};
function make12(parse) {
  const self = Object.create(Proto5);
  self.parse = parse;
  return self;
}
var map7 = /* @__PURE__ */ dual(2, (self, f) => {
  return make12((provider) => map5(self.parse(provider), f));
});
var mapOrFail = /* @__PURE__ */ dual(2, (self, f) => {
  return make12((provider) => flatMap3(self.parse(provider), f));
});
var orElse = /* @__PURE__ */ dual(2, (self, that) => {
  return make12((provider) => catch_3(self.parse(provider), (error) => that(error).parse(provider)));
});
function all3(arg) {
  const configs = Array.isArray(arg) ? arg : (Symbol.iterator in arg) ? [...arg] : arg;
  if (Array.isArray(configs)) {
    return make12((provider) => all2(configs.map((config) => config.parse(provider))));
  } else {
    return make12((provider) => all2(map2(configs, (config) => config.parse(provider))));
  }
}
function isMissingDataOnly(issue) {
  switch (issue._tag) {
    case "MissingKey":
      return true;
    case "InvalidType":
    case "InvalidValue":
      return isNone2(issue.actual) || isSome2(issue.actual) && issue.actual.value === undefined;
    case "OneOf":
      return issue.actual === undefined;
    case "Encoding":
      return isNone2(issue.actual) || isSome2(issue.actual) && issue.actual.value === undefined ? true : isMissingDataOnly(issue.issue);
    case "Pointer":
    case "Filter":
      return isMissingDataOnly(issue.issue);
    case "UnexpectedKey":
      return false;
    case "Forbidden":
      return false;
    case "Composite":
    case "AnyOf":
      return issue.issues.every(isMissingDataOnly);
  }
}
var withDefault2 = /* @__PURE__ */ dual(2, (self, defaultValue) => {
  return orElse(self, (err) => {
    if (isSchemaError(err.cause)) {
      const issue = err.cause.issue;
      if (isMissingDataOnly(issue)) {
        return succeed6(defaultValue);
      }
    }
    return fail7(err.cause);
  });
});
var option3 = (self) => self.pipe(map7(some2), withDefault2(none2()));
var unwrap2 = (wrapped) => {
  if (isConfig(wrapped))
    return wrapped;
  return make12((provider) => {
    const entries = Object.entries(wrapped);
    const configs = entries.map(([key, config]) => unwrap2(config).parse(provider).pipe(map5((value3) => [key, value3])));
    return all2(configs).pipe(map5(Object.fromEntries));
  });
};
var dump = /* @__PURE__ */ fnUntraced2(function* (provider, path) {
  const stat = yield* provider.load(path);
  if (stat === undefined)
    return;
  switch (stat._tag) {
    case "Value":
      return stat.value;
    case "Record": {
      if (stat.value !== undefined)
        return stat.value;
      const out = {};
      for (const key of stat.keys) {
        const child = yield* dump(provider, [...path, key]);
        if (child !== undefined)
          out[key] = child;
      }
      return out;
    }
    case "Array": {
      if (stat.value !== undefined)
        return stat.value;
      const out = [];
      for (let i = 0;i < stat.length; i++) {
        out.push(yield* dump(provider, [...path, i]));
      }
      return out;
    }
  }
});
var recur2 = /* @__PURE__ */ fnUntraced2(function* (ast, provider, path) {
  switch (ast._tag) {
    case "Objects": {
      const out = {};
      for (const ps of ast.propertySignatures) {
        const name2 = ps.name;
        if (typeof name2 === "string") {
          const value3 = yield* recur2(ps.type, provider, [...path, name2]);
          if (value3 !== undefined)
            out[name2] = value3;
        }
      }
      if (ast.indexSignatures.length > 0) {
        const stat = yield* provider.load(path);
        if (stat && stat._tag === "Record") {
          for (const is3 of ast.indexSignatures) {
            const matches = _is(is3.parameter);
            for (const key of stat.keys) {
              if (!Object.hasOwn(out, key) && matches(key)) {
                const value3 = yield* recur2(is3.type, provider, [...path, key]);
                if (value3 !== undefined)
                  out[key] = value3;
              }
            }
          }
        }
      }
      return out;
    }
    case "Arrays": {
      const stat = yield* provider.load(path);
      if (stat && stat._tag === "Value")
        return stat.value;
      const out = [];
      for (let i = 0;i < ast.elements.length; i++) {
        out.push(yield* recur2(ast.elements[i], provider, [...path, i]));
      }
      return out;
    }
    case "Union":
      return yield* dump(provider, path);
    case "Suspend":
      return yield* recur2(ast.thunk(), provider, path);
    default: {
      const stat = yield* provider.load(path);
      if (stat === undefined)
        return;
      if (stat._tag === "Value")
        return stat.value;
      if (stat._tag === "Record" && stat.value !== undefined)
        return stat.value;
      if (stat._tag === "Array" && stat.value !== undefined)
        return stat.value;
      return;
    }
  }
});
function schema2(codec, path) {
  const codecStringTree = toCodecStringTree(codec);
  const decodeUnknownEffect2 = decodeUnknownEffect(codecStringTree);
  const codecStringTreeEncoded = toEncoded(codecStringTree.ast);
  const defaultPath = typeof path === "string" ? [path] : path ?? [];
  return make12((provider) => {
    const path2 = provider.prefix ? [...provider.prefix, ...defaultPath] : defaultPath;
    return recur2(codecStringTreeEncoded, provider, defaultPath).pipe(flatMapEager2((tree) => decodeUnknownEffect2(tree).pipe(mapErrorEager2((issue) => new SchemaError(path2.length > 0 ? new Pointer(path2, issue) : issue)))), mapErrorEager2((cause) => new ConfigError(cause)));
  });
}
var TrueValues = /* @__PURE__ */ Literals(["true", "yes", "on", "1", "y"]);
var FalseValues = /* @__PURE__ */ Literals(["false", "no", "off", "0", "n"]);
var Boolean3 = /* @__PURE__ */ Literals([...TrueValues.literals, ...FalseValues.literals]).pipe(/* @__PURE__ */ decodeTo2(Boolean2, /* @__PURE__ */ transform2({
  decode: (value3) => value3 === "true" || value3 === "yes" || value3 === "on" || value3 === "1" || value3 === "y",
  encode: (value3) => value3 ? "true" : "false"
})));
var Duration2 = /* @__PURE__ */ String4.pipe(/* @__PURE__ */ decodeTo2(Duration, {
  decode: /* @__PURE__ */ transformOrFail((s) => {
    const d = fromInput(s);
    return match(d, {
      onNone: () => fail5(new InvalidValue(some2(s))),
      onSome: succeed5
    });
  }),
  encode: /* @__PURE__ */ forbidden(() => "Encoding Duration is not supported")
}));
var Port = /* @__PURE__ */ Int.check(/* @__PURE__ */ isBetween({
  minimum: 1,
  maximum: 65535
}));
var LogLevel = /* @__PURE__ */ Literals(values);
var Record2 = (key, value3, options) => {
  const record2 = Record(key, value3);
  const recordString = String4.pipe(decodeTo2(Record(String4, String4), splitKeyValue2(options)), decodeTo2(record2));
  return Union2([record2, recordString]);
};
function fail7(err) {
  return make12(() => fail5(new ConfigError(err)));
}
function succeed6(value3) {
  return make12(() => succeed5(value3));
}
function string3(name2) {
  return schema2(String4, name2);
}
function nonEmptyString(name2) {
  return schema2(NonEmptyString, name2);
}
function number3(name2) {
  return schema2(Number5, name2);
}
function finite(name2) {
  return schema2(Finite, name2);
}
function int3(name2) {
  return schema2(Int, name2);
}
function literal(literal2, name2) {
  return schema2(Literal2(literal2), name2);
}
function boolean3(name2) {
  return schema2(Boolean3, name2);
}
function duration(name2) {
  return schema2(Duration2, name2);
}
function port(name2) {
  return schema2(Port, name2);
}
function logLevel(name2) {
  return schema2(LogLevel, name2);
}
function redacted(name2) {
  return schema2(Redacted(String4), name2);
}
function url(name2) {
  return schema2(URL2, name2);
}
function date2(name2) {
  return schema2(DateValid, name2);
}
var nested2 = /* @__PURE__ */ dual(2, (self, name2) => make12((provider) => self.parse(nested(provider, name2))));
// ../../packages/database/dist/schema.js
var exports_schema2 = {};
__export(exports_schema2, {
  sessions: () => sessions,
  sessionEvents: () => sessionEvents
});
var sessions = sqliteTable("sessions", {
  id: integer2("id").primaryKey({ autoIncrement: true }),
  sessionId: text2("session_id").notNull().unique(),
  status: text2("status", { enum: ["IDLE", "RUNNING", "PENDING_APPROVAL"] }).notNull().default("IDLE"),
  agent: text2("agent", { enum: ["ClaudeCode", "Codex", "OpenCode"] }).notNull(),
  sessionName: text2("session_name").notNull(),
  workingDirectory: text2("working_directory").notNull(),
  createdAt: integer2("created_at", { mode: "timestamp" }).notNull(),
  updatedAt: integer2("updated_at", { mode: "timestamp" }).notNull()
});
var sessionEvents = sqliteTable("session_events", {
  id: integer2("id").primaryKey({ autoIncrement: true }),
  sessionId: text2("session_id"),
  eventName: text2("event_name").notNull(),
  toolName: text2("tool_name"),
  cwd: text2("cwd"),
  payload: text2("payload").notNull(),
  createdAt: integer2("created_at", { mode: "timestamp" }).notNull()
}, (table) => [
  index("session_events_session_id_idx").on(table.sessionId),
  index("session_events_event_name_idx").on(table.eventName),
  index("session_events_created_at_idx").on(table.createdAt)
]);

// ../../packages/database/dist/client.js
class Database2 extends exports_Context.Service()("Database") {
}
var layer = (config) => exports_Layer.effect(Database2, exports_Effect.gen(function* () {
  const filename = config?.filename ?? (yield* exports_Config.string("DATABASE_PATH").pipe(exports_Config.withDefault("./local.db")));
  const client = yield* exports_Effect.acquireRelease(exports_Effect.sync(() => new BunDatabase(filename)), (db) => exports_Effect.sync(() => db.close()));
  return drizzle({ client, schema: exports_schema2 });
}));
// ../../packages/database/dist/ensure-schema.js
var SCHEMA_STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS sessions (
    id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
    session_id text NOT NULL,
    status text DEFAULT 'IDLE' NOT NULL,
    agent text NOT NULL,
    session_name text NOT NULL,
    working_directory text NOT NULL,
    created_at integer NOT NULL,
    updated_at integer NOT NULL
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS sessions_session_id_unique ON sessions (session_id)`,
  `CREATE TABLE IF NOT EXISTS session_events (
    id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
    session_id text,
    event_name text NOT NULL,
    tool_name text,
    cwd text,
    payload text NOT NULL,
    created_at integer NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS session_events_session_id_idx ON session_events (session_id)`,
  `CREATE INDEX IF NOT EXISTS session_events_event_name_idx ON session_events (event_name)`,
  `CREATE INDEX IF NOT EXISTS session_events_created_at_idx ON session_events (created_at)`
];
var ensureSchema = gen2(function* () {
  const db = yield* Database2;
  yield* sync3(() => {
    db.run(sql.raw("PRAGMA journal_mode = WAL"));
    db.run(sql.raw("PRAGMA busy_timeout = 5000"));
    for (const statement of SCHEMA_STATEMENTS) {
      db.run(sql.raw(statement));
    }
  });
});
// ../../packages/database/dist/migrate.js
import { fileURLToPath } from "url";

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/migrator.js
import crypto2 from "crypto";
import fs, { existsSync, readdirSync } from "fs";
import { join } from "path";
function readMigrationFiles(config) {
  if (fs.existsSync(`${config.migrationsFolder}/meta/_journal.json`))
    throw Error('We detected that you have old drizzle-kit migration folders. You must upgrade drizzle-kit and run "drizzle-kit up"');
  const migrationFolderTo = config.migrationsFolder;
  const migrationQueries = [];
  const migrations = readdirSync(migrationFolderTo).map((subdir) => ({
    path: join(migrationFolderTo, subdir, "migration.sql"),
    name: subdir
  })).filter((it) => existsSync(it.path));
  migrations.sort((a, b) => a.name.localeCompare(b.name));
  for (const migration of migrations) {
    const migrationPath = migration.path;
    const migrationDate = migration.name.slice(0, 14);
    const query = fs.readFileSync(migrationPath).toString();
    const result3 = query.split("--> statement-breakpoint").map((it) => {
      return it;
    });
    const millis2 = formatToMillis(migrationDate);
    migrationQueries.push({
      sql: result3,
      bps: true,
      folderMillis: millis2,
      hash: crypto2.createHash("sha256").update(query).digest("hex"),
      name: migration.name
    });
  }
  return migrationQueries;
}

// ../../node_modules/.bun/drizzle-orm@1.0.0-rc.1+548e7bbc21f60809/node_modules/drizzle-orm/bun-sqlite/migrator.js
function migrate(db, config) {
  if (Array.isArray(config) || "migrationsJournal" in config) {
    const journal = Array.isArray(config) ? config : config.migrationsJournal;
    const migrationsTable = Array.isArray(config) ? undefined : config.migrationsTable;
    const migrations2 = journal.map((d) => ({
      sql: d.sql.split("--> statement-breakpoint"),
      folderMillis: d.timestamp,
      hash: "",
      bps: true,
      name: d.name
    }));
    return db.dialect.migrate(migrations2, db.session, { migrationsTable });
  }
  const migrations = readMigrationFiles(config);
  return db.dialect.migrate(migrations, db.session, config);
}

// ../../packages/database/dist/migrate.js
var migrationsFolder = fileURLToPath(new URL("../drizzle", import.meta.url));
var migrate2 = gen2(function* () {
  const db = yield* Database2;
  yield* sync3(() => migrate(db, { migrationsFolder }));
});
// ../../packages/database/dist/paths.js
import { homedir } from "os";
import { join as join2 } from "path";
var DEFAULT_DATABASE_PATH = join2(homedir(), ".local", "agent-sessions", "sessions.db");
function resolveDatabasePath() {
  const override = process.env.AGENT_SESSIONS_DB;
  return override && override.length > 0 ? override : DEFAULT_DATABASE_PATH;
}
// ../../packages/database/dist/errors.js
class DrizzleError2 extends TaggedErrorClass()("DrizzleError", {
  message: String4,
  cause: Defect
}) {
  static fromUnknown(error) {
    const message = error instanceof Error ? error.message : String(error);
    return new DrizzleError2({ message, cause: error });
  }
}

// ../../packages/actions/dist/helpers/derive-status.js
var CLAUDE_RUNNING_EVENTS = new Set([
  "UserPromptSubmit",
  "PreToolUse",
  "PostToolUse",
  "PostToolBatch",
  "SubagentStart"
]);
var CODEX_RUNNING_EVENTS = new Set(["UserPromptSubmit", "PreToolUse", "PostToolUse"]);
var IDLE_EVENTS = new Set(["Stop", "SessionEnd"]);
function deriveStatus(agent, eventName, context3 = {}) {
  if (agent === "ClaudeCode") {
    if (eventName === "PermissionRequest")
      return "PENDING_APPROVAL";
    if (eventName === "Notification") {
      if (context3.notificationType === "permission_prompt")
        return "PENDING_APPROVAL";
      if (context3.notificationType === "idle_prompt")
        return "IDLE";
      return null;
    }
    if (CLAUDE_RUNNING_EVENTS.has(eventName))
      return "RUNNING";
    if (IDLE_EVENTS.has(eventName))
      return "IDLE";
    return null;
  }
  if (eventName === "Notification")
    return "PENDING_APPROVAL";
  if (CODEX_RUNNING_EVENTS.has(eventName))
    return "RUNNING";
  if (IDLE_EVENTS.has(eventName))
    return "IDLE";
  return null;
}

// ../../packages/actions/dist/helpers/apply-hook-event.js
function parseRecord(rawPayload) {
  const trimmed = rawPayload.trim();
  if (!trimmed)
    return {};
  try {
    const parsed = JSON.parse(trimmed);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}
function stringField(record2, ...keys2) {
  for (const key of keys2) {
    const value3 = record2[key];
    if (typeof value3 === "string" && value3.length > 0)
      return value3;
  }
  return;
}
function extractHookFields(rawPayload) {
  const record2 = parseRecord(rawPayload);
  return {
    sessionId: stringField(record2, "session_id", "sessionId"),
    cwd: stringField(record2, "cwd"),
    toolName: stringField(record2, "tool_name", "toolName"),
    notificationType: stringField(record2, "notification_type", "notificationType"),
    eventName: stringField(record2, "hook_event_name", "hookEventName")
  };
}
var applyHookEvent = exports_Effect.fn("actions.applyHookEvent")(function* (input) {
  const db = yield* Database2;
  const fields = extractHookFields(input.rawPayload);
  const eventName = input.eventName || fields.eventName || "unknown";
  const cwd = fields.cwd ?? input.fallbackCwd;
  const sessionId = fields.sessionId;
  const payload = input.rawPayload.trim() ? input.rawPayload : "{}";
  const status = deriveStatus(input.agent, eventName, { notificationType: fields.notificationType });
  yield* exports_Effect.try({
    try: () => db.transaction((tx2) => {
      tx2.insert(sessionEvents).values({
        sessionId: sessionId ?? null,
        eventName,
        toolName: fields.toolName ?? null,
        cwd,
        payload,
        createdAt: input.now
      }).run();
      if (!sessionId)
        return;
      const existing = tx2.select().from(sessions).where(eq(sessions.sessionId, sessionId)).get();
      if (existing) {
        tx2.update(sessions).set({
          ...status ? { status } : {},
          workingDirectory: cwd,
          updatedAt: input.now
        }).where(eq(sessions.sessionId, sessionId)).run();
      } else {
        const directoryName = basename(cwd);
        tx2.insert(sessions).values({
          sessionId,
          status: status ?? "IDLE",
          agent: input.agent,
          sessionName: directoryName.length > 0 ? directoryName : sessionId,
          workingDirectory: cwd,
          createdAt: input.now,
          updatedAt: input.now
        }).run();
      }
    }),
    catch: DrizzleError2.fromUnknown
  });
});
// ../../packages/actions/dist/helpers/session-helpers.js
var createSession = exports_Effect.fn("actions.createSesssion")(function* (payload) {
  const db = yield* Database2;
  const result3 = yield* exports_Effect.try({
    try: () => db.insert(sessions).values(payload).returning().get(),
    catch: DrizzleError2.fromUnknown
  });
  return result3;
});
var createSessionEvent = exports_Effect.fn("actions.createSessionEvent")(function* (payload) {
  const db = yield* Database2;
  const result3 = yield* exports_Effect.try({
    try: () => db.insert(sessionEvents).values(payload).returning().get(),
    catch: DrizzleError2.fromUnknown
  });
  return result3;
});
var listSessions = exports_Effect.fn("actions.listSessions")(function* (filters) {
  const db = yield* Database2;
  const result3 = yield* exports_Effect.try({
    try: () => db.select().from(sessions).where(buildSessionsFilters(filters)).orderBy(desc(sessions.updatedAt)).all(),
    catch: DrizzleError2.fromUnknown
  });
  return result3;
});
var listSessionEvents = exports_Effect.fn("actions.listSessionEvents")(function* (filters) {
  const db = yield* Database2;
  const result3 = yield* exports_Effect.try({
    try: () => db.select().from(sessionEvents).where(buildSessionEventsFilters(filters)).orderBy(desc(sessionEvents.createdAt)).all(),
    catch: DrizzleError2.fromUnknown
  });
  return result3;
});
function buildSessionsFilters(payload) {
  const filters = [];
  if (payload.agent) {
    filters.push(eq(sessions.agent, payload.agent));
  }
  if (payload.workingDirectory) {
    filters.push(eq(sessions.workingDirectory, payload.workingDirectory));
  }
  if (payload.status) {
    filters.push(eq(sessions.status, payload.status));
  }
  if (payload.fromTimestamp) {
    filters.push(gte(sessions.createdAt, payload.fromTimestamp));
  }
  if (payload.toTimestamp) {
    filters.push(lte(sessions.createdAt, payload.toTimestamp));
  }
  return and(...filters);
}
function buildSessionEventsFilters(payload) {
  const filters = [];
  if (payload.sessionId) {
    filters.push(eq(sessionEvents.sessionId, payload.sessionId));
  }
  if (payload.eventName) {
    filters.push(eq(sessionEvents.eventName, payload.eventName));
  }
  if (payload.fromTimestamp) {
    filters.push(gte(sessionEvents.createdAt, payload.fromTimestamp));
  }
  if (payload.toTimestamp) {
    filters.push(lte(sessionEvents.createdAt, payload.toTimestamp));
  }
  return and(...filters);
}

// ../../packages/actions/dist/sessions-repo.js
class SessionsRepo extends Service()("@actions/Sessions") {
  static layerDrizzle = effect(SessionsRepo, gen2(function* () {
    const db = yield* Database2;
    const provideDb = provideService2(Database2, db);
    return SessionsRepo.of({
      listSessions: (filters) => listSessions(filters).pipe(provideDb),
      createSession: (payload) => createSession(payload).pipe(provideDb),
      listSessionEvents: (filters) => listSessionEvents(filters).pipe(provideDb),
      createSessionEvent: (payload) => createSessionEvent(payload).pipe(provideDb),
      applyHookEvent: (input) => applyHookEvent(input).pipe(provideDb)
    });
  }));
}
// src/index.ts
var AGENT_BY_COMMAND = {
  claude: "ClaudeCode",
  codex: "Codex"
};
var USAGE = "usage: agent-sessions-cli <claude|codex> <HookEventName>   (hook payload on stdin)";
async function main() {
  const [command, eventArg] = process.argv.slice(2);
  const agent = command ? AGENT_BY_COMMAND[command] : undefined;
  if (!agent) {
    process.stderr.write(`[agent-sessions-cli] unknown command: ${command ?? "(none)"}
${USAGE}
`);
    return;
  }
  const eventName = eventArg ?? process.env.AGENT_SESSIONS_HOOK_EVENT ?? "unknown";
  const rawPayload = await Bun.stdin.text();
  const databasePath = resolveDatabasePath();
  mkdirSync(dirname(databasePath), { recursive: true });
  const appLayer = SessionsRepo.layerDrizzle.pipe(provideMerge(layer({ filename: databasePath })));
  const input = {
    agent,
    eventName,
    rawPayload,
    fallbackCwd: process.cwd(),
    now: new Date
  };
  const program = gen2(function* () {
    yield* ensureSchema;
    const repo = yield* SessionsRepo;
    yield* repo.applyHookEvent(input);
  }).pipe(provide4(appLayer));
  await runPromise2(program);
}
main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`[agent-sessions-cli] failed to record hook event: ${message}
`);
}).finally(() => {
  process.exit(0);
});
