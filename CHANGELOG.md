# Changelog

## [1.3.0](https://github.com/georgeguimaraes/review.nvim/compare/v1.2.0...v1.3.0) (2026-01-15)


### Features

* multi-line comments with box-style virtual text ([693b9f2](https://github.com/georgeguimaraes/review.nvim/commit/693b9f25c7ba7ab53c6bb4f62e26fcc5eea42ac7))


### Bug Fixes

* issue keymaps not cleared on close ([#5](https://github.com/georgeguimaraes/review.nvim/issues/5)) ([98a1986](https://github.com/georgeguimaraes/review.nvim/commit/98a19868c389c03e007c8cbcb2e31d01fc020a6f))

## [1.2.0](https://github.com/georgeguimaraes/review.nvim/compare/v1.1.0...v1.2.0) (2026-01-15)


### Features

* add commit picker and auto-jump to first hunk ([d828f63](https://github.com/georgeguimaraes/review.nvim/commit/d828f63c5ca2d50f8adaebfb33015cfb25fd0708))
* add sidekick.nvim integration ([1c183ee](https://github.com/georgeguimaraes/review.nvim/commit/1c183eef5a1ee55f086806e2f7131de480d6c28f))
* auto-export comments to clipboard on close ([2584566](https://github.com/georgeguimaraes/review.nvim/commit/258456653c8d4617f88e46222c03a54d96e113b1))
* auto-switch to unified view on open ([d1a6a42](https://github.com/georgeguimaraes/review.nvim/commit/d1a6a426bd6976cb7bec57ac1ced991cdec61af4))
* change keymaps - C for export, C-r for clear ([29f9f8b](https://github.com/georgeguimaraes/review.nvim/commit/29f9f8b78cd80efe4e5ac93979e859720174b69e))
* improve UX with focus management and export preview ([cfa3561](https://github.com/georgeguimaraes/review.nvim/commit/cfa35612d2add9799dab716cf1accdd092c8aac6))
* initial implementation of diffnotes.nvim ([2939401](https://github.com/georgeguimaraes/review.nvim/commit/2939401e054d148557e280b282ac3680fa7401ac))
* persist comments per branch ([4433a78](https://github.com/georgeguimaraes/review.nvim/commit/4433a78b6d77ae7dd080d2e8a7006e36be5adc14))


### Bug Fixes

* export preview buffer handling and focus restoration ([b48249a](https://github.com/georgeguimaraes/review.nvim/commit/b48249a51dff5bf14726979401b2ff1e32bcd951))
* focus picker window on open ([507b111](https://github.com/georgeguimaraes/review.nvim/commit/507b11119e4285061d918d5c36c0ddce9c2111c9))
* mark release PR as tagged after release creation ([b2a17b0](https://github.com/georgeguimaraes/review.nvim/commit/b2a17b03d888d9b2c4dcdba6c05f944eea748ff1))
* picker keymaps and remove select all option ([23c850b](https://github.com/georgeguimaraes/review.nvim/commit/23c850b362e88910ab47ee02173db684de530340))
* remove invalid diff1_plain layout config ([7ef7d72](https://github.com/georgeguimaraes/review.nvim/commit/7ef7d72591dc2ab73dd71bf449d15f5a5bbcf5a4))
* toggle layout for current entry explicitly ([001668d](https://github.com/georgeguimaraes/review.nvim/commit/001668d3da5217a91296015dad64a9af47fa26f9))


### Miscellaneous

* add Apache 2.0 license ([54c7aca](https://github.com/georgeguimaraes/review.nvim/commit/54c7aca13227c4eee82f0a59c33f8b34d54017b0))
* add release-please config and manifest files ([71ad52a](https://github.com/georgeguimaraes/review.nvim/commit/71ad52acd8b96d51fd94d463cce2b8cb4a1b033b))
* **main:** release 1.0.0 ([#1](https://github.com/georgeguimaraes/review.nvim/issues/1)) ([78c1c97](https://github.com/georgeguimaraes/review.nvim/commit/78c1c9742b3a43825d0d02753b72f08b4a38dab8))
* **main:** release 1.1.0 ([#2](https://github.com/georgeguimaraes/review.nvim/issues/2)) ([f47e2a4](https://github.com/georgeguimaraes/review.nvim/commit/f47e2a4363cfcb22a259d09460df3531e988f986))


### Documentation

* add keymap examples to README ([f5e49ec](https://github.com/georgeguimaraes/review.nvim/commit/f5e49ec1b36f072a37414472df3b587687c43868))
* credit tuicr as inspiration ([845b334](https://github.com/georgeguimaraes/review.nvim/commit/845b334af0f542348a328dedd5381b22fe85bc38))
* simplify config with opts ([4cccd98](https://github.com/georgeguimaraes/review.nvim/commit/4cccd98fa414725950811bf6c892a540d78a9e26))
* update README with new features ([763d682](https://github.com/georgeguimaraes/review.nvim/commit/763d68205798b09e864662cd171a3ef41762e31c))
* update repo username ([8ec6803](https://github.com/georgeguimaraes/review.nvim/commit/8ec68033afb2c91c60b0a81506f44a750376d2d4))


### Code Refactoring

* migrate from diffview.nvim to codediff.nvim ([416c10d](https://github.com/georgeguimaraes/review.nvim/commit/416c10db6bc6f6ca5b2331cb0cd7f3a330df416a))
* rename plugin from diffnotes to review ([07f7dfd](https://github.com/georgeguimaraes/review.nvim/commit/07f7dfd7868d4b1d726f8f6b4c73b4ec0afd2d9d))
* use title-based notifications ([1a3b3a5](https://github.com/georgeguimaraes/review.nvim/commit/1a3b3a5d3006daab0a37c19e94e0ef479d5ce636))


### Tests

* add integration tests for marks rendering ([fe7d884](https://github.com/georgeguimaraes/review.nvim/commit/fe7d884a386c7d17e04a63f0a256384a61141788))


### Continuous Integration

* add GitHub Actions workflow for tests ([839ef48](https://github.com/georgeguimaraes/review.nvim/commit/839ef4807fbeb4c6c6e1f961160d81fc4de2520b))
* add release-please workflows ([b90cbe9](https://github.com/georgeguimaraes/review.nvim/commit/b90cbe9032168426fe70ddc357d81aa08105740a))


### Performance Improvements

* only update changed line on selection toggle ([c2f7285](https://github.com/georgeguimaraes/review.nvim/commit/c2f7285d8b2ed3847e9ff8c82244be2267be2654))

## [1.1.0](https://github.com/georgeguimaraes/review.nvim/compare/v1.0.0...v1.1.0) (2026-01-15)


### Features

* add commit picker and auto-jump to first hunk ([d828f63](https://github.com/georgeguimaraes/review.nvim/commit/d828f63c5ca2d50f8adaebfb33015cfb25fd0708))
* add sidekick.nvim integration ([1c183ee](https://github.com/georgeguimaraes/review.nvim/commit/1c183eef5a1ee55f086806e2f7131de480d6c28f))
* change keymaps - C for export, C-r for clear ([29f9f8b](https://github.com/georgeguimaraes/review.nvim/commit/29f9f8b78cd80efe4e5ac93979e859720174b69e))


### Bug Fixes

* focus picker window on open ([507b111](https://github.com/georgeguimaraes/review.nvim/commit/507b11119e4285061d918d5c36c0ddce9c2111c9))
* mark release PR as tagged after release creation ([b2a17b0](https://github.com/georgeguimaraes/review.nvim/commit/b2a17b03d888d9b2c4dcdba6c05f944eea748ff1))
* picker keymaps and remove select all option ([23c850b](https://github.com/georgeguimaraes/review.nvim/commit/23c850b362e88910ab47ee02173db684de530340))


### Miscellaneous

* add Apache 2.0 license ([54c7aca](https://github.com/georgeguimaraes/review.nvim/commit/54c7aca13227c4eee82f0a59c33f8b34d54017b0))
* add release-please config and manifest files ([71ad52a](https://github.com/georgeguimaraes/review.nvim/commit/71ad52acd8b96d51fd94d463cce2b8cb4a1b033b))


### Documentation

* add keymap examples to README ([f5e49ec](https://github.com/georgeguimaraes/review.nvim/commit/f5e49ec1b36f072a37414472df3b587687c43868))
* simplify config with opts ([4cccd98](https://github.com/georgeguimaraes/review.nvim/commit/4cccd98fa414725950811bf6c892a540d78a9e26))


### Performance Improvements

* only update changed line on selection toggle ([c2f7285](https://github.com/georgeguimaraes/review.nvim/commit/c2f7285d8b2ed3847e9ff8c82244be2267be2654))

## 1.0.0 (2026-01-14)


### Features

* auto-export comments to clipboard on close ([2584566](https://github.com/georgeguimaraes/review.nvim/commit/258456653c8d4617f88e46222c03a54d96e113b1))
* auto-switch to unified view on open ([d1a6a42](https://github.com/georgeguimaraes/review.nvim/commit/d1a6a426bd6976cb7bec57ac1ced991cdec61af4))
* improve UX with focus management and export preview ([cfa3561](https://github.com/georgeguimaraes/review.nvim/commit/cfa35612d2add9799dab716cf1accdd092c8aac6))
* initial implementation of diffnotes.nvim ([2939401](https://github.com/georgeguimaraes/review.nvim/commit/2939401e054d148557e280b282ac3680fa7401ac))
* persist comments per branch ([4433a78](https://github.com/georgeguimaraes/review.nvim/commit/4433a78b6d77ae7dd080d2e8a7006e36be5adc14))


### Bug Fixes

* export preview buffer handling and focus restoration ([b48249a](https://github.com/georgeguimaraes/review.nvim/commit/b48249a51dff5bf14726979401b2ff1e32bcd951))
* remove invalid diff1_plain layout config ([7ef7d72](https://github.com/georgeguimaraes/review.nvim/commit/7ef7d72591dc2ab73dd71bf449d15f5a5bbcf5a4))
* toggle layout for current entry explicitly ([001668d](https://github.com/georgeguimaraes/review.nvim/commit/001668d3da5217a91296015dad64a9af47fa26f9))
