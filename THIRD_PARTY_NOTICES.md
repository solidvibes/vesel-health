# Third-party notices

Vesel is licensed under the Apache License 2.0 (see `LICENSE` and `NOTICE`). It uses the packages below, each under its own licence. None of them is copied into this repo: Swift Package Manager and uv fetch them when you build or set up.

Swift packages are pinned to exact versions in each `Package.swift`, including the two the Polar BLE SDK brings in, so every build uses the versions below. Python versions are locked in `server/uv.lock` and installed at set-up.

Licence names come from each package's licence file (Swift) or its package metadata (Python).

## Swift (iPhone app, widgets, Mac app)

| Package | Pinned | Licence | Copyright |
|---|---|---|---|
| [Polar BLE SDK](https://github.com/polarofficial/polar-ble-sdk) | 8.5.0 | Polar Software Development Kit Limited License Agreement (`Polar_SDK_License.txt` in the SDK) | Copyright © Polar Electro Oy. All rights reserved. |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.11.1 | MIT | Copyright (C) 2015-2025 Gwendal Roué |
| [swift-protobuf](https://github.com/apple/swift-protobuf) | 1.39.0 | Apache-2.0 | Copyright (c) 2014 - 2016 Apple Inc. and the project authors |
| [Zip](https://github.com/marmelroy/Zip) | 2.1.2 | MIT | Copyright (c) 2015 Roy Marmelstein |

swift-protobuf and Zip come in with the Polar BLE SDK. GRDB.swift is used by the app, the widgets and the Mac app.

### Polar BLE SDK

Vesel uses the Polar BLE SDK to read the band over Bluetooth. The SDK is the property of Polar Electro Oy and is used under its Software Development Kit Limited License Agreement: <https://github.com/polarofficial/polar-ble-sdk/blob/master/Polar_SDK_License.txt>. The SDK's own third-party software is listed in its `ThirdPartySoftwareListing.txt`: <https://github.com/polarofficial/polar-ble-sdk/blob/master/ThirdPartySoftwareListing.txt>.

Polar, Polar Loop, Polar Flow and Nightly Recharge are names of Polar Electro Oy. Vesel is not affiliated with or endorsed by Polar Electro.

## Python (backup server)

Installed with the server:

| Package | Locked | Licence | Copyright |
|---|---|---|---|
| fastapi | 0.162.0 | MIT | Copyright (c) 2018 Sebastián Ramírez |
| starlette | 1.10.0 | BSD-3-Clause | Copyright © 2018, Encode OSS Ltd |
| pydantic | 2.14.1 | MIT | Copyright (c) 2017 to present Pydantic Services Inc. and individual contributors |
| pydantic-core | 2.50.1 | MIT | Copyright (c) 2022 Samuel Colvin |
| uvicorn | 0.54.0 | BSD-3-Clause | Copyright © 2017-present, Encode OSS Ltd |
| anyio | 4.15.1 | MIT | Copyright (c) 2018 Alex Grönholm |
| idna | 3.20 | BSD-3-Clause | Copyright (c) 2013-2026, Kim Davies and contributors |
| h11 | 0.16.0 | MIT | Copyright (c) 2016 Nathaniel J. Smith and other contributors |
| click | 8.5.0 | BSD-3-Clause | Copyright 2014 Pallets |
| annotated-types | 0.8.0 | MIT | Copyright (c) 2022 the contributors |
| annotated-doc | 0.0.5 | MIT | Copyright (c) 2025 Sebastián Ramírez |
| typing-extensions | 4.16.0 | PSF-2.0 | Python Software Foundation (see the package's licence) |
| typing-inspection | 0.4.4 | MIT | Copyright (c) Pydantic Services Inc. 2025 to present |
| opentelemetry-api (pulled in by fastapi) | 1.45.1 | Apache-2.0 | OpenTelemetry Authors |

For the tests only (not installed by the Mac app):

| Package | Locked | Licence | Copyright |
|---|---|---|---|
| httpx2 | 2.16.0 | BSD-3-Clause | Copyright © 2026 to present Pydantic Services Inc. and individual contributors; Copyright © 2019, Encode OSS Ltd |
| httpcore2 | 2.16.0 | BSD-3-Clause | Copyright © 2026 to present Pydantic Services Inc. and individual contributors; Copyright © 2020, Encode OSS Ltd |
| truststore | 0.10.5 | MIT | Copyright (c) 2022 Seth Michael Larson |
| httpx2-jsfetch (browser Python only, never installed here) | 1.0 | BSD-3-Clause | Hood Chatham (author, per package metadata) |
| pytest | 9.1.1 | MIT | Copyright (c) 2004 Holger Krekel and others |
| pluggy | 1.7.0 | MIT | Copyright (c) 2015 holger krekel |
| iniconfig | 2.3.1 | MIT | Copyright (c) 2010 - 2023 Holger Krekel and others |
| packaging | 26.3 | Apache-2.0 OR BSD-2-Clause | Copyright (c) Donald Stufft and individual contributors |
| pygments | 2.21.0 | BSD-2-Clause | Copyright (c) 2006-2022 by the respective authors |
| colorama (Windows only) | 0.4.6 | BSD-3-Clause (its `LICENSE.txt`) | Copyright (c) 2010 Jonathan Hartley |

## Licence texts

Copied from each Swift package at its pinned version. These go into the built iPhone and Mac apps. The Python packages are not part of any build: uv downloads them at set-up, each with its own licence file.

### GRDB.swift (MIT)

```
Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### Zip (MIT)

```
The MIT License (MIT)

Copyright (c) 2015 Roy Marmelstein

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### swift-protobuf (Apache-2.0)

The Apache License 2.0 text is the same as Vesel's own [`LICENSE`](LICENSE). swift-protobuf has no NOTICE file. Its licence file adds:

```
## Runtime Library Exception to the Apache 2.0 License: ##


As an exception, if you use this Software to compile your source code and
portions of this Software are embedded into the binary product as a result,
you may redistribute such product without providing attribution as would
otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.
```

### Polar BLE SDK

Its own licence, linked above: `Polar_SDK_License.txt` in the SDK.
