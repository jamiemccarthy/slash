Summary: Slashdot-Like Automated Story Homepage
Name: slash
Version: 2.0.0_pre1
Release: 1
Copyright: GPL
Group: Applications/Internet
Source: ftp://slashcode.sourceforge.net/pub/slashcode/slash-2.0.0-pre1.tar.gz
BuildRoot: /var/tmp/%{name}-buildroot

%description
Slash is a database-driven news and message board, using Perl, Apache and mySQL.
It is the code that runs Slashdot. For forums, support, mailing lists, etc.
please see the Slashcode site.

%prep
%setup -q -n slash-2.0.0-pre1

%build
make RPM_OPT_FLAGS="$RPM_OPT_FLAGS" SLASH_PREFIX=$RPM_BUILD_ROOT/usr/local/slash INIT=$RPM_BUILD_ROOT/etc USER=99 GROUP=99 RPM=1

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/etc/init.d
mkdir -p $RPM_BUILD_ROOT/etc/rc3.d
mkdir -p $RPM_BUILD_ROOT/etc/rc6.d
make install RPM_OPT_FLAGS="$RPM_OPT_FLAGS" SLASH_PREFIX=/var/tmp/%{name}-buildroot/usr/local/slash INIT=/var/tmp/%{name}-buildroot/etc USER=99 GROUP=99 RPM=1

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr (-,nobody,nobody)
%doc AUTHORS CHANGES COPYING INSTALL MANIFEST MANIFEST.SKIP README

/etc/init.d/slash
/etc/rc3.d/S99slash
/etc/rc6.d/K99slash
/usr/lib/perl5/site_perl/5.6.0/i386-linux/auto/Slash*
/usr/lib/perl5/site_perl/5.6.0/i386-linux/Slash*
/usr/lib/perl5/site_perl/5.6.0/Slash*
/usr/share/man/man3/Slash*
/usr/local/slash*

%changelog
* Wed Mar 21 2001 Jonathan Pater <pater@slashdot.org>
- Initial Package
