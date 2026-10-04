module.exports = [
  {
    files: ["**/*.js"],
    ignores: ["node_modules/**"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: {
        console: "readonly",
        exports: "writable",
        module: "writable",
        require: "readonly",
      },
    },
    rules: {
      "no-undef": "error",
      "no-unused-vars": [
        "error",
        {argsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_"},
      ],
      quotes: ["error", "double", {allowTemplateLiterals: true}],
      semi: ["error", "always"],
    },
  },
];
