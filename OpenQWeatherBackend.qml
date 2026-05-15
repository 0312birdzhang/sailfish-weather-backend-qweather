// SPDX-FileCopyrightText: 2026 Sailfish contributors
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.6
import Nemo.Configuration 1.0
import "BackendUtils.js" as BackendUtils
import "WeatherTypeDescriptions.js" as WeatherTypeDescriptions

QtObject {

    function providerId() {
        return "qweather"
    }

    readonly property ConfigurationValue providerAppKey: ConfigurationValue {
        key: "/sailfish/weather/" + providerId() + "_app_id"
        defaultValue: ""
    }

    function providerTitle() {
        return "和风天气"
    }

    function requiresApiKey() {
        return true
    }

    function apiKeyInstructions() {
        return "如何获取 API Key:"
               + "<ol><li>打开<b><a href='https://dev.qweather.com/'>和风天气开放平台</a></b> 并注册一个开发者账号。</li>"
               + "<li>创建一个应用，类型选<b>WebAPI</b>，点击新建。</li>"
               + "<li>获取你的 <b>KEY</b> 和对应的 <b>API 域名</b>。</li>"
               + "<li>API HOST 通过 <a href='https://console.qweather.com/setting'>https://console.qweather.com/setting</a> 进入查看</li>"
               + "<li>KEY 通过 <a href='https://console.qweather.com/project?lang=zh'>https://console.qweather.com/project?lang=zh</a> 进入查看</li>"
               + "<li>将域名和KEY用<strong>英文逗号</strong>分隔填写，例如：<code>devapi.qweather.com,你的KEY</code></li></ol>"
    }

    function attributionText() {
        return "天气数据来自<a href='https://www.qweather.com/'>和风天气</a>."
    }

    function shortAttributionText() {
        return "天气数据来自和风天气"
    }

    function fetchToken(weatherRequest, apiKey) {
        weatherRequest.token = ""
        return true
    }

    function requestHeaders() {
        return {
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
        }
    }

    function parseApiConfig() {
        var config = providerAppKey.value
        if (!config) {
            return { host: "", key: "" }
        }
        var parts = config.split(",")
        if (parts.length >= 2) {
            return { host: parts[0].trim(), key: parts[1].trim() }
        }
        return { host: "", key: config.trim() }
    }

    function currentWeatherUrl(weather) {
        var config = parseApiConfig()
        if (!config.host || !config.key) {
            return ""
        }
        return "https://" + config.host + "/v7/weather/now?location=" + weather.longitude + "," + weather.latitude + "&key=" + config.key
    }

    function latestObservationUrl(weather) {
        return currentWeatherUrl(weather)
    }

    function forecastUrl(weather, isHourly) {
        var config = parseApiConfig()
        if (!config.host || !config.key) {
            return ""
        }
        if (isHourly) {
            return "https://" + config.host + "/v7/weather/24h?location=" + weather.longitude + "," + weather.latitude + "&key=" + config.key
        } else {
            return "https://" + config.host + "/v7/weather/7d?location=" + weather.longitude + "," + weather.latitude + "&key=" + config.key
        }
    }

    function searchLocationUrl(filter, language) {
        var config = parseApiConfig()
        if (!config.host || !config.key) {
            return ""
        }
        return "https://" + config.host + "/geo/v2/city/lookup?location=" + encodeURIComponent(filter) + "&key=" + config.key + "&limit=20"
    }

    function handleCurrentWeatherResult(result) {
        if (!result || result.code !== "200" || !result.now) {
            return undefined
        }

        var now = result.now
        var weatherCode = now.icon || "100"
        var isDay = isDaytimeIcon(weatherCode)

        var weather = getWeatherData(weatherCode, isDay, now.text, now.cloud)
        weather.timestamp = new Date(now.obsTime.replace(/-/g, '/'))
        weather.temperature = parseFloat(now.temp)
        weather.feelsLikeTemperature = parseFloat(now.feelsLike)

        if (result.location) {
            weather.latitude = parseFloat(result.location.lat)
            weather.longitude = parseFloat(result.location.lon)
        }

        if (now.windDir) {
            weather.windDirection = windDirectionToDegree(now.windDir)
        }
        if (now.windSpeed) {
            weather.maximumWindSpeed = parseWindSpeed(now.windSpeed)
        }

        if (now.humidity !== undefined) {
            weather.humidity = parseInt(now.humidity)
        }

        return weather
    }

    function handleForecastResult(result, hourly, visibleCount, minimumHourlyRange) {
        if (!result || result.code !== "200") {
            return undefined
        }

        return hourly ? handleHourlyForecastResult(result, visibleCount, minimumHourlyRange)
                      : handleDailyForecastResult(result)
    }

    function handleHourlyForecastResult(result, visibleCount, minimumHourlyRange) {
        var hourly = result.hourly
        if (!hourly || hourly.length === 0) {
            return undefined
        }

        var weatherData = []
        for (var i = 0; i < hourly.length && weatherData.length < visibleCount + 1; i++) {
            var data = hourly[i]

            if (!data || !data.temp) {
                continue
            }

            var weatherCode = data.icon || "100"
            var isDay = isDaytimeIcon(weatherCode)

            var weather = getWeatherData(weatherCode, isDay, data.text, data.cloud)
            weather.timestamp = new Date(data.fxTime.replace(/-/g, '/'))
            weather.temperature = parseFloat(data.temp)

            if (data.feelsLike) {
                weather.feelsLikeTemperature = parseFloat(data.feelsLike)
            }

            if (data.windDir) {
                weather.windDirection = windDirectionToDegree(data.windDir)
            }
            if (data.windSpeed) {
                weather.maximumWindSpeed = parseWindSpeed(data.windSpeed)
            }
            if (data.precip) {
                weather.accumulatedPrecipitation = data.precip
            } else {
                weather.accumulatedPrecipitation = 0
            }

            if (data.pop !== undefined) {
                weather.precipitationProbability = parseInt(data.pop)
            }

            weatherData[weatherData.length] = weather
        }

        return BackendUtils.normalizeHourlyTemperatures(
                    weatherData, visibleCount, minimumHourlyRange, true)
    }

    function handleDailyForecastResult(result) {
        var daily = result.daily
        if (!daily || daily.length === 0) {
            return undefined
        }

        var weatherData = []
        var maxDays = 7
        for (var i = 0; i < maxDays && i < daily.length; i++) {
            var data = daily[i]

            if (!data || !data.tempMax || !data.tempMin) {
                continue
            }

            var weatherCode = data.iconDay || "100"
            var isDay = isDaytimeIcon(weatherCode)

            var descriptionText = data.textDay && data.textNight && data.textDay !== data.textNight
                ? data.textDay + "转" + data.textNight
                : (data.textDay || data.textNight || "")
            var weather = getWeatherData(weatherCode, isDay, descriptionText, data.cloud)
            weather.timestamp = new Date(data.fxDate.replace(/-/g, '/'))
            weather.high = Math.floor(parseFloat(data.tempMax))
            weather.low = Math.round(parseFloat(data.tempMin))

            if (data.precip) {
                weather.accumulatedPrecipitation = data.precip
            } else {
                weather.accumulatedPrecipitation = 0
            }

            if (data.windSpeedDay) {
                weather.maximumWindSpeed = parseWindSpeed(data.windSpeedDay)
            }
            if (data.wind360Day) {
                weather.windDirection = parseFloat(data.wind360Day)
            }

            weatherData[weatherData.length] = weather
        }

        return weatherData.length > 0 ? weatherData : undefined
    }

    function handleSearchLocationResult(result) {
        if (!result || result.code !== "200") {
            return undefined
        }

        var locations = []
        var results = result.location
        if (!results || results.length === 0) {
            return []
        }

        for (var i = 0; i < results.length; i++) {
            var location = results[i]
            var lat = parseFloat(location.lat)
            var lon = parseFloat(location.lon)

            if (isNaN(lat) || isNaN(lon)) {
                continue
            }

            var locationId = parseInt(location.id, 10)
            if (!isFinite(locationId) || locationId <= 0) {
                locationId = hashLatLon(lat, lon, 15, 0x51574541)
            }

            locations[locations.length] = {
                "id": locationId,
                "name": location.name || "",
                "state": location.adm1 || "",
                "country": location.country || "",
                "adminArea": location.adm1 || "",
                "adminArea2": location.adm2 || "",
                "latitude": lat,
                "longitude": lon
            }
        }

        return locations.length > 0 ? locations : undefined
    }

    function handleObservationResult(result) {
        return result && result.location ? result.location.name : ""
    }

    function externalUrl(weather) {
        return "https://github.com/0312birdzhang/sailfish-weather-backend-qweather"
    }

    function providerImage() {
        return "image://theme/qweather?"
    }

    function smallProviderImage() {
        return "image://theme/qweather-small?"
    }

    function isDaytimeIcon(icon) {
        if (!icon) return true
        var code = parseInt(icon, 10)
        if (isNaN(code)) return true

        if (code >= 100 && code <= 154) {
            return code <= 104
        }
        if (code >= 300 && code <= 318) {
            return code <= 318
        }
        if (code >= 350 && code <= 399) {
            return false
        }
        return true
    }

    function getWeatherData(weatherCode, isDay, descriptionText, cloudiness) {
        var weatherTypeCode = weatherTypeFromQWeather(weatherCode)
        var timePrefix = isDay === 0 ? "n" : "d"
        return {
            "description": descriptionText || "",
            "weatherType": weatherType(timePrefix + weatherTypeCode),
            "cloudiness": cloudiness !== undefined ? parseInt(cloudiness) : 0
        }
    }

    function weatherTypeFromQWeather(weatherCode) {
        if (!weatherCode || weatherCode.length < 3) {
            return "400"
        }

        var code = parseInt(weatherCode, 10)
        if (isNaN(code)) return "400"

        switch (code) {
        case 100: return "000"
        case 101: return "300"
        case 102: return "200"
        case 103: return "200"
        case 104: return "400"
        case 150: return "000"
        case 151: return "300"
        case 152: return "200"
        case 153: return "200"
        case 300: return "210"
        case 301: return "310"
        case 302: return "440"
        case 303: return "440"
        case 304: return "440"
        case 305: return "210"
        case 306: return "430"
        case 307: return "430"
        case 308: return "440"
        case 309: return "210"
        case 310: return "440"
        case 311: return "440"
        case 312: return "440"
        case 313: return "410"
        case 314: return "410"
        case 315: return "410"
        case 316: return "420"
        case 317: return "430"
        case 318: return "430"
        case 350: return "420"
        case 351: return "420"
        case 399: return "430"
        case 400: return "212"
        case 401: return "322"
        case 402: return "432"
        case 403: return "432"
        case 404: return "211"
        case 405: return "411"
        case 406: return "221"
        case 407: return "222"
        case 408: return "212"
        case 409: return "312"
        case 410: return "412"
        case 456:
        case 457: return "422"
        case 499: return "432"
        case 500: return "500"
        case 501: return "600"
        case 502: return "500"
        case 503:
        case 504: return "610"
        case 507:
        case 508: return "610"
        case 509:
        case 510: return "600"
        case 511: return "500"
        case 512:
        case 513: return "500"
        case 514:
        case 515: return "600"
        case 900: return "000"
        case 901: return "000"
        case 999: return "400"
        default: return "400"
        }
    }

    function cloudinessFromQWeather(weatherCode) {
        if (!weatherCode || weatherCode.length < 3) {
            return 100
        }

        var code = parseInt(weatherCode, 10)
        if (isNaN(code)) return 100

        if (code === 100 || code === 800) return 0
        if (code >= 101 && code <= 103) return 50
        if (code === 104 || code >= 300) return 100

        if (code >= 150 && code <= 153) return 50
        if (code >= 350 && code <= 399) return 100

        if (code >= 400 && code <= 499) return 100

        return 100
    }

    function weatherType(code) {
        if (code.length === 4) {
            return code
        }
        console.warn("Invalid weather code")
        return ""
    }

    function windDirectionToDegree(dir) {
        var directions = {
            "N": 0,
            "NNE": 22.5,
            "NE": 45,
            "ENE": 67.5,
            "E": 90,
            "ESE": 112.5,
            "SE": 135,
            "SSE": 157.5,
            "S": 180,
            "SSW": 202.5,
            "SW": 225,
            "WSW": 247.5,
            "W": 270,
            "WNW": 292.5,
            "NW": 315,
            "NNW": 337.5
        }
        return directions[dir] !== undefined ? directions[dir] : 0
    }

    function parseWindSpeed(value) {
        return Math.round(parseFloat(value))
    }

    function hashLatLon(lat, lon, precisionBits, seed) {
        precisionBits = precisionBits || 16
        seed = seed || 0

        var latScaled = Math.floor(((lat + 90) / 180) * (1 << precisionBits))
        var lonScaled = Math.floor(((lon + 180) / 360) * (1 << precisionBits))
        var hash = ((latScaled << precisionBits) | lonScaled) ^ seed
        hash = hash & 0x7fffffff
        return hash > 0 ? hash : 1
    }
}
