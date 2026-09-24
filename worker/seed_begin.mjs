// MoonBit の標準ライブラリは、Map のハッシュ用の乱数シードをモジュールの読み込み時（グローバルスコープ）に
// crypto.getRandomValues で作る。Workers はグローバルスコープでの乱数生成を禁止しているので、
// jsapi.js を読み込む間だけ Math.random を使う実装に差し替え、seed_end.mjs で元に戻す。
// シードはハッシュの偏りを防ぐためのもので、暗号用途ではない。
export const original = crypto.getRandomValues;
crypto.getRandomValues = function (array) {
  for (let i = 0; i < array.length; i += 1) array[i] = Math.floor(Math.random() * 2 ** 32);
  return array;
};
