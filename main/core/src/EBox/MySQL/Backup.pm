# Copyright (C) 2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use warnings;

package EBox::MySQL::Backup;

use Time::Piece;
use EBox::Sudo;
use File::Basename;

my $BP_DIR = '/tmp/bp';

sub _dbuser
{
    return 'bkpuser';
}

sub _dbpass
{
    return 'foobar';
}

sub chains
{
    my @chainsDirs = sort glob("$BP_DIR/[0-9][0-9][0-9][0-9]*");
    my @chains = map {
        my $dir = $_;
        my @elements = sort glob("$dir/[0-9][0-9][0-9][0-9]*");
        @elements = grep { -d $_} @elements;
        [@elements];
    } grep { -d $_ } @chainsDirs;
    return \@chains;
}

sub _newChain
{
    my $time = gmtime(time())->datetime;
    my $path = "$BP_DIR/$time";
    if (EBox::Sudo::fileTest('-e', $path)) {
        throw EBox::Exceptions::Internal("Directory for backup chain $path alredy exists");
    }

    EBox::Sudo::root("mkdir -p '$path'");
    return $path;
}

sub fullBackup
{
    my $dir = _newChain();
    my $cmd = _baseCmd();
    $cmd .= ' ' . $dir;
    EBox::Sudo::root($cmd);
}

sub incrementalBackup
{
    my ($baseDir) = @_;
    my $chainDir = dirname($baseDir);
    my $cmd = _baseCmd();
    $cmd .= ' --incremental --incremental-basedir=' . $baseDir;
    $cmd .= " $chainDir ";
    EBox::Sudo::root($cmd);
}

sub _baseCmd
{
    my $cmd ='innobackupex';
    $cmd .= ' --user ' . _dbuser();
    $cmd .= ' --password ' . _dbpass();
    return $cmd;
}

1;
