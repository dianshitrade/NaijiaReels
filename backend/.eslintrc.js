module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  parserOptions: { project: 'tsconfig.json', tsconfigRootDir: __dirname, sourceType: 'module' },
  plugins: ['@typescript-eslint'],
  extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended'],
  env: { node: true, jest: true },
  ignorePatterns: ['.eslintrc.js', 'dist'],
  rules: { '@typescript-eslint/no-explicit-any': 'error' },
};
