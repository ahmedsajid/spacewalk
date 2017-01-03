#!/bin/bash
# 
# Written by ahmed.sajid
# Version 1.0
#
# Most of these instructions are taken from https://access.redhat.com/articles/1355053
# 
# This script downloads repos using reposync from Red Hat. RHEL 6 requires a repo/config file to read URLs etc. RHEL 7 doesn't need it since this information is available in /etc/yum.repos.d/redhat.repo file
# Repodata is created using createrepo
# After all the repos are sycned locally, these are then sync into spacewalk 
# Make sure you have /etc/yum.repos.d/rhel-6.repo file present with correct URLs pointing to RHEL 6 repos

echo "--------------------------------------------------"
echo "Start: $(date)    Host: $(hostname)"
echo "--------------------------------------------------"

# List of REPOS to sync from Red Hat
RHEL6_REPOS="rhel-6-server-rpms rhel-6-server-extras-rpms rhel-6-server-optional-rpms rhel-6-server-thirdparty-oracle-java-rpms rhel-6-server-rh-common-rpms rhel-6-server-supplementary-rpms"
RHEL7_REPOS="rhel-7-server-rpms rhel-7-server-extras-rpms rhel-7-server-optional-rpms rhel-7-server-thirdparty-oracle-java-rpms rhel-7-server-rh-common-rpms rhel-7-server-supplementary-rpms"

# Path to local repo directory
REPO_DIR="/opt/repos"

# Check if yum-utils and createrepo is installed

if ! rpm -qa | grep -q "yum-utils\|createrepo";then
	echo "Please install yum-utils and createrepo before running this script again"
	echo "yum install yum-utils createrepo"
	exit 1
fi

# Check if rhel-6.repo file exists
if [ ! -f /etc/yum.repos.d/rhel-6.repo ];then
	echo "RHEL 6 repo file doesn't exists /etc/yum.repos.d/rhel-6.repo"
	exit 1
fi

# loop through list of REPOS, sync them locally and create repodata
for REPO in $RHEL6_REPOS $RHEL7_REPOS
do

	echo "--------------------------------------------------"
	echo "$REPO: - reposync starting - $(date)"
	echo "--------------------------------------------------"

	# Syncing repositories locally
	# Remove newest-only to create an exact mirror of Red Hat repos. This is used to save disk space
	# Remove quiet for debugging
	reposync --quiet --downloadcomps --download-metadata --newest-only --delete --arch x86_64 --download_path $REPO_DIR/ --repoid $REPO  

	# Creates repodata folder
	createrepo --quiet --checksum sha256 --checkts --update --workers=2 --groupfile $REPO_DIR/$REPO/comps.xml $REPO_DIR/$REPO

	# If productid.gz exists extract it
	if [ -f $REPO_DIR/$REPO/productid.gz ];then
		gunzip $REPO_DIR/$REPO/productid.gz
	# update repomd.xml file with productid
		modifyrepo $REPO_DIR/$REPO/productid $REPO_DIR/$REPO/repodata/
	fi
	
	# extract updateinfo file
	gunzip -c $(ls -rt $REPO_DIR/$REPO/*updateinfo.xml.gz | tail -n 1) > $REPO_DIR/$REPO/updateinfo.xml

	# Patch updateinfo file https://bugzilla.redhat.com/show_bug.cgi?id=1354496
	# line cause the problem
	# for e.g.,
	# <reference href="https://bugzilla.redhat.com/show_bug.cgi?id=1148230" type="bugzilla" id="RHSA-2014:1801" title="CVE-2014-3675 shim: out-of-bounds memory read flaw in DHCPv6 packet processing" />
	# should be
	# <reference href="https://bugzilla.redhat.com/show_bug.cgi?id=1148230" type="bugzilla" id="1148230" title="CVE-2014-3675 shim: out-of-bounds memory read flaw in DHCPv6 packet processing" />
	# Spacewalk doesn't like it for obvious reason
	# If this patch isn't applied, erratas dont get synced and you will get an error something similar to the following while running spacewalk-repo-sync
	# ERROR: invalid literal for int() with base 10: 'RHSA-2014:1801'
	
	sed -i 's/=\([0-9]*\)\(" type="bugzilla" id="\)RH[BSE]A-[0-9]\{4\}:[0-9]\{4\}/=\1\2\1/' $REPO_DIR/$REPO/updateinfo.xml

	# update repomd.xml with new updateinfo.xml
	modifyrepo $REPO_DIR/$REPO/updateinfo.xml $REPO_DIR/$REPO/repodata/

	# change permissions on repo directory
	chmod 755 $REPO_DIR/$REPO/repodata
	chmod 644 $REPO_DIR/$REPO/repodata/*
done

# Changing ownership to apache for /opt/repos
chown -R apache: $REPO_DIR


# List of CentOS7 channels to sync into spacewalk
CENTOS7_CHANNELS="centos7-x86_64 centosplus-centos7-x86_64 epel-centos7-x86_64 extras-centos7-x86_64 fasttrack-centos7-x86_64 spacewalk-client-centos7-x86_64 updates-centos7-x86_64"

# List of RHEL6 & RHEL7 channels to sync into spacewalk
RHEL6_CHANNELS="epel-rhel6-x86_64 extras-rhel6-x86_64 mysql56-advanced-rhel6-x86_64 mysql57-commercial-rhel6-x86_64 optional-rhel6-x86_64 oracle-java-rhel6-x86_64 ossec-rhel6-x86_64 percona-sql-rhel6-x86_64 postgresql-rhel6-x86_64 rh-common-rhel6-x86_64 rhel6-x86_64 spacewalk-client-rhel6-x86_64 subversion1.9-rhel6-x86_64 supplementary-rhel6-x86_64 vmware-tools-rhel6-x86_64 vmware-vfabric-suite-rhel6-x86_64"
RHEL7_CHANNELS="epel-rhel7-x86_64 extras-rhel7-x86_64 mysql56-advanced-rhel7-x86_64 mysql57-commercial-rhel7-x86_64 optional-rhel7-x86_64 oracle-java-rhel7-x86_64 ossec-rhel7-x86_64 percona-sql-rhel7-x86_64 postgresql-rhel7-x86_64 rh-common-rhel7-x86_64 rhel7-x86_64 spacewalk-client-rhel7-x86_64 subversion1.9-rhel7-x86_64 supplementary-rhel7-x86_64"

# Loop through the channels and run spacewalk-repo-sync
for CHANNEL in $CENTOS7_CHANNELS $RHEL6_CHANNELS $RHEL7_CHANNELS
do
	echo "--------------------------------------------------"
	echo "$CHANNEL: - spacewalk-repo-sync starting - $(date)"
	echo "--------------------------------------------------"
   	spacewalk-repo-sync --channel $CHANNEL
done

echo "--------------------------------------------------"
echo "Finish: $(date)   Host: $(hostname)"
echo "--------------------------------------------------"
