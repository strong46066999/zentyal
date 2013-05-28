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

# XXX enable InnoDB engine

use strict;
use warnings;

package EBox::MySQL::Backup;

use Time::Piece;
use EBox::Sudo;
use EBox::Global;
use EBox::Service;
use File::Basename;

my $BP_DIR = '/tmp/bp';
use constant MYSQL_DATA_DIR => '/var/lib/mysql';
use constant MYSQL_SERVER_USER => 'mysql';
use constant DB_PWD_FILE => '/var/lib/zentyal/conf/zentyal-mysql.passwd';

sub _dbuser
{
    return 'root';
}

my $dbPass;
sub _dbpass
{
    unless ($dbPass) {
        my ($pass) = @{EBox::Sudo::root('/bin/cat ' . DB_PWD_FILE)};
        $dbPass = $pass;
    }

    return $dbPass;
}

sub chains
{
    my @chainsDirs = sort glob("$BP_DIR/[0-9][0-9][0-9][0-9]*.d");
    my @chains =  grep { -d $_ } @chainsDirs;
    return \@chains;
}

sub _chainBackups
{
    my ($dir) = @_;
    my @elements = sort glob("$dir/[0-9][0-9][0-9][0-9]*");
    @elements = grep { -d $_} @elements;
    return \@elements;
}

sub _newChain
{
    my $time = gmtime(time())->datetime;
    $time =~ s/:/-/g;
    my $path = "$BP_DIR/$time.d";
    if (EBox::Sudo::fileTest('-e', $path)) {
        throw EBox::Exceptions::Internal("Directory for backup chain $path alredy exists");
    }

    EBox::Sudo::root("mkdir -p '$path'");
    return $path;
}

sub backup
{
    my $chains = chains();
    if (not @{ $chains }) {
        fullBackup();
    } else {
        my $lastBase = _chainBackups($chains->[-1])->[1];
        if (not $lastBase) {
            throw EBox::Exceptions::Internal("Cannot found last backup for last chain");
        }
        incrementalBackup($lastBase);
    }

}

sub fullBackup
{
    my $dir = _newChain();
    my $cmd = _baseCmd();
    $cmd .= ' --compress ' . $dir;
    EBox::Sudo::root($cmd);
}

sub incrementalBackup
{
    my ($baseDir) = @_;
    my $chainDir = dirname($baseDir);
    my $cmd = _baseCmd();
    $cmd .= ' --compress --incremental --incremental-basedir=' . $baseDir;
    $cmd .= " $chainDir ";
    EBox::Sudo::root($cmd);
}

sub _stopDBServer
{
    my $global = EBox::Global->getInstance();
    my @modulesToStop = qw(logs);
    foreach my $modName (@modulesToStop) {
        my $mod = $global->modInstance($modName);
        if ($mod and $mod->isEnabled() and $mod->isRunning()) {
            $mod->stopService();
        }
    }

    EBox::Service::manage('mysql', 'stop');
}

sub _startDBServer
{
    EBox::Service::manage('mysql', 'start');

    my $global = EBox::Global->getInstance();
    my @modulesToStop = qw(logs);
    foreach my $modName (@modulesToStop) {
        my $mod = $global->modInstance($modName);
        if ($mod and $mod->isEnabled() and not $mod->isRunning()) {
            $mod->restartService();
        }
    }
}

sub restoreChain
{
    my ($dir) = @_;
    if (not -d $dir) {
        throw EBox::Exceptions::Internal("$dir is not a directory");
    }
    my ($full, @incrementals) = @{ _chainBackups($dir) };
    if (not $full) {
        throw EBox::Exceptions::Internal("Backup chain has not any backup");
    }


    if (@incrementals) {
        _prepareIncrementalBackups($full, @incrementals);
    }

    _prepareFullBackup($full);
    _stopDBServer();
    _restoreFullBackup($full);
    _startDBServer();
}

sub _prepareIncrementalBackups
{
    my ($full, @incrementals) = @_;
    my $cmd = _baseCmd();
    $cmd .= " --apply-log --redo-only $full";
    EBox::Sudo::root($cmd);

    for (my $i=0; $i < @incrementals; $i++) {
        my $redo = (($i+1) < @incrementals);
        $cmd = _baseCmd();
        $cmd .= ' --apply-log';
        if ($redo) {
            $cmd .= ' --redo-only';
        }
        $cmd .= ' ' . $full;
        $cmd .= ' --incremental-dir=' . $incrementals[$i];
        EBox::Sudo::root($cmd);
    }
}

sub _prepareFullBackup
{
    my ($full) = @_;
    my $cmd = _baseCmd();
    $cmd .= " --apply-log $full";
    EBox::Sudo::root($cmd);
}

# mysql msut be stopped at this point
sub _restoreFullBackup
{
    my ($full) = @_;
    # we don't make a backup of old data becuase we assume that is a fresh
    # isntall without nothing worth on it
    EBox::Sudo::root('rm -rf ' . MYSQL_DATA_DIR . '/*');

    my $cmd = _baseCmd(). ' --copy-back ' . $full; # XXX use move instead of
                                                   # copy?
    EBox::Sudo::root($cmd);
    EBox::Sudo::root('chown -R '.
                     MYSQL_SERVER_USER . '.' . MYSQL_SERVER_USER .
                     ' ' . MYSQL_DATA_DIR
                    );
}


sub _baseCmd
{
    my $cmd ='innobackupex';
    $cmd .= ' --user ' . _dbuser();
    $cmd .= ' --password ' . _dbpass();
    return $cmd;
}

1;
