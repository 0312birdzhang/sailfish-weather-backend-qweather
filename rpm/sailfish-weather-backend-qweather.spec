Name:           sailfish-weather-backend-qweather
Version:        1.0.0
Release:        1%{?dist}
Summary:        和风天气后端 for Sailfish Weather (Sailfish OS)
License:        GPLv3
URL:            https://github.com/0312birdzhang/sailfish-weather-backend-qweather
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Packager:       0312birdzhang
Requires:       sailfish-weather >= 1.3.5

%description
此包为 Sailfish Weather 应用提供和风天气后端支持。
它安装前端所需的 QML 后端文件和图标 PNG。

%prep
%setup -q

%build
# no build step

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/share/sailfish-weather/backends
mkdir -p %{buildroot}/usr/share/themes/sailfish-default/silica/icons-monochrome

# copy QML backend files
cp -a OpenQWeatherBackend.qml %{buildroot}/usr/share/sailfish-weather/backends/ 2>/dev/null || true

# copy PNG icons (top-level or icons/ as shipped)
cp -a *.png %{buildroot}/usr/share/themes/sailfish-default/silica/icons-monochrome/ 2>/dev/null || true

%files
%defattr(-,root,root,-)
%doc README.md
/usr/share/sailfish-weather/backends/OpenQWeatherBackend.qml
/usr/share/themes/sailfish-default/silica/icons-monochrome/qweather.png
/usr/share/themes/sailfish-default/silica/icons-monochrome/qweather-small.png

%changelog
* Tue May 14 2026 0312birdzhang - 1.0.0-1
- Initial package
