module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  parserOptions: { project: false, ecmaVersion: 'latest', sourceType: 'module' },
  env: { node: true, es2023: true },
  plugins: ['@typescript-eslint', 'import', 'simple-import-sort', 'unused-imports'],
  extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended', 'plugin:import/recommended', 'plugin:import/typescript', 'prettier'],
  rules: {
    'unused-imports/no-unused-imports': 'error',
    'no-unused-vars': 'off',
    '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    'simple-import-sort/imports': 'warn',
    'simple-import-sort/exports': 'warn',
    'import/order': 'off',
    'import/no-unresolved': 'off',
    '@typescript-eslint/explicit-function-return-type': 'off',
    reportUnusedDisableDirectives: 'error',
  },
  settings: {
    'import/resolver': {
      typescript: { project: '.' },
      node: true,
    },
  },
  ignorePatterns: ['dist/', 'node_modules/', 'coverage/'],
};
