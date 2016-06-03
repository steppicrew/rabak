# Copyright 1999-2016 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

EAPI=5

inherit perl-module eutils

inherit git-r3
EGIT_REPO_URI="https://github.com/steppicrew/${PN}.git"

DESCRIPTION="rabak is a backup utility for files and databases based on rsync."
HOMEPAGE="http://www.raisin.de/rabak"

SLOT="0"
LICENSE="Artistic"
KEYWORDS="~alpha ~amd64 ~ppc ~ppc64 ~sparc ~x86"
IUSE=""

RDEPEND=">=dev-lang/perl-5.8.2
        >=sys-apps/util-linux-2.12-r4
        >=sys-apps/coreutils-5.0.91-r4
        >=net-misc/openssh-3.7.1_p2-r1
        >=net-misc/rsync-2.6.0
        dev-perl/Data-UUID
        dev-perl/IPC-Run
        dev-perl/MailTools
        dev-perl/Digest-SHA1
        dev-perl/DBD-SQLite
        >=virtual/perl-Getopt-Long-2.36"

src_compile() {
    cd "${WORKDIR}/${PF}"

    perl-module_src_prepare
    perl-module_src_compile
}

src_install () {
    cd "${WORKDIR}/${PF}"

    perl-module_src_install

    dodoc LICENSE README TODO CHANGELOG INSTALL

    # Move rabak to bin where it belongs.
    dobin rabak
    # Copy sample config files
    insinto /etc
    doins -r etc/rabak
    # Make raba.secret.cf readable only for root
    fperms 0400 "/etc/rabak/rabak.secret.cf"
    # Copy misc files
    insinto "/usr/share/${PF}"
    doins -r share/*
}

pkg_postinst() {
    elog
    elog "The configuration file: /etc/rabak/rabak.sample.cf "
    elog "  has been installed. "
    elog "This is a template. "
    elog "Copy, or move, the above file to: /etc/rabak/rabak.cf "
    elog "Note that upgrading will update the template, not real config. "
    elog
    elog "Please pay special attention to permissions of "
    elog "  /etc/rabak/rabak.secret.cf"
    elog
}

