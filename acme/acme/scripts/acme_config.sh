#!/bin/sh
source /jffs/softcenter/scripts/base.sh
eval `dbus export acme`
acme_root="/jffs/softcenter/acme"
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
LOGFILE=/tmp/acme_log.log
mkdir -p /tmp/etc
mkdir -p /jffs/ssl

start_issue(){
	case "$acme_provider" in
	1)
		# ali_dns
		echo_date 使用Aliyun dns接口申请证书... >> $LOGFILE
		sed -i '/Ali_Key/d' /jffs/softcenter/acme/account.conf
		sed -i '/Ali_Secret/d' /jffs/softcenter/acme/account.conf
		echo -e "Ali_Key='$acme_ali_arg1'\nAli_Secret='$acme_ali_arg2'" >> /jffs/softcenter/acme/account.conf
		dnsapi=dns_ali
		;;
	2)
		# dnspod
		echo_date 使用Dnspod接口申请证书... >> $LOGFILE
		sed -i '/DP_Id/d' /jffs/softcenter/acme/account.conf
		sed -i '/DP_Key/d' /jffs/softcenter/acme/account.conf
		echo -e "DP_Id='$acme_dp_arg1'\nDP_Key='$acme_dp_arg2'" >> /jffs/softcenter/acme/account.conf
		dnsapi=dns_dp
		;;
	3)
		# cloudxns
		echo_date 使用CloudXNS接口申请证书... >> $LOGFILE
		sed -i '/CX_Key/d' /jffs/softcenter/acme/account.conf
		sed -i '/CX_Secret/d' /jffs/softcenter/acme/account.conf
		echo -e "CX_Key='$acme_xns_arg1'\nCX_Secret='$acme_xns_arg2'" >> /jffs/softcenter/acme/account.conf
		dnsapi=dns_cx
		;;
	4)
		# cloudflare
		echo_date 使用CloudFlare接口申请证书... >> $LOGFILE
		sed -i '/CF_Key/d' /jffs/softcenter/acme/account.conf
		sed -i '/CF_Email/d' /jffs/softcenter/acme/account.conf
		echo -e "CF_Key='$acme_cf_arg1'\nCF_Email='$acme_cf_arg2'" >> /jffs/softcenter/acme/account.conf
		dnsapi=dns_cf
		;;
	5)
		# godaddy
		echo_date 使用GoDaddy接口申请证书... >> $LOGFILE
		sed -i '/GD_Key/d' /jffs/softcenter/acme/account.conf
		sed -i '/GD_Secret/d' /jffs/softcenter/acme/account.conf
		echo -e "GD_Key='$acme_gd_arg1'\nGD_Secret='$acme_gd_arg2'" >> /jffs/softcenter/acme/account.conf
		dnsapi=dns_gd
		;;
	esac
	sleep 1
	cd $acme_root
	#./acme.sh --home "$acme_root" --issue --dns $dnsapi -d $acme_domain -d $acme_subdomain.$acme_domain --use-wget --log-level 2 --debug
	./acme.sh --home "$acme_root" --issue --dns $dnsapi -d $acme_subdomain.$acme_domain --use-wget --insecure
}

install_cert(){
	cd $acme_root
	./acme.sh --home "$acme_root" --installcert -d $acme_subdomain.$acme_domain --keypath /tmp/etc/key.pem --fullchainpath /tmp/etc/cert.pem --reloadcmd "service restart_httpd"
	./acme.sh --home "$acme_root" --installcert -d $acme_subdomain.$acme_domain --keypath /jffs/ssl/key.pem --fullchainpath /jffs/ssl/cert.pem --reloadcmd "service restart_httpd"
	# install to /tmp/etc for aicloud
	aicloud_enable=`nvram get aicloud_enable`
	cat /tmp/etc/key.pem > /tmp/etc/server.pem
	echo "" \ >> /etc/server.pem
	cat /tmp/etc/cert.pem >> /tmp/etc/server.pem
	if [ "$aicloud_enable" == "1" ];then
		service restart_webdav
	fi	
}

force_renew(){
	$acme_root/acme.sh --cron --force --home $acme_root
	if [ "$?" == "1" ];then
		echo_date 强制更新失败！！ >> $LOGFILE
	else
		echo_date 强制更新成功！！ >> $LOGFILE
		install_cert
	fi
}

del_all_cert(){
	cd $acme_root
	find . -name "fullchain.cer*"|sed 's/\/fullchain.cer//g'|xargs rm -rf
	rm -rf /tmp/etc/*.pem
	rm -rf /jffs/softcenter/acme/*$acme_domain
	rm -rf /jffs/softcenter/acme/http.header
}

add_cron(){
	sed -i '/acme/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	cru a acme_renew "47 * * * * $acme_root/acme.sh --cron --home $acme_root"
}

del_cron(){
	sed -i '/acme/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
}

check_md5(){
	md5sum_cer_jffs=$(md5sum /tmp/etc/cert.pem | sed 's/ /\n/g'| sed -n 1p)
	md5sum_cer_acme=$(md5sum "$acme_subdomain.$acme_domain/fullchain.cer" | sed 's/ /\n/g'| sed -n 1p)
	md5sum_key_jffs=$(md5sum /tmp/etc/key.pem | sed 's/ /\n/g'| sed -n 1p)
	md5sum_key_acme=$(md5sum "$acme_subdomain.$acme_domain/$acme_subdomain.$acme_domain.key" | sed 's/ /\n/g'| sed -n 1p)	
}

check_cert(){
	SUB=`openssl x509 -text -in "$acme_subdomain.$acme_domain"/fullchain.cer | grep -A 1 "Subject Alternative Name"|tail -n1|sed 's/,//g'|sed 's/DNS://g'|sed "s/$acme_domain//g"|sed 's/\.//g'|sed 's/^[ \t]*//g'|sed 's/[ \t]*$//g'`
	EXPIRE=`openssl x509 -text -in "$acme_subdomain.$acme_domain"/fullchain.cer|grep "Not After"|sed 's/Not After ://g'|sed 's/^[ \t]*//g'`
}

apply_now(){
	echo_date 开始为$acme_subdomain.$acme_domain申请证书！ >> $LOGFILE
	echo_date 证书申请过程可能会持续3分钟，请不要关闭或刷新本网页！ >> $LOGFILE
	sleep 2
	start_issue >> $LOGFILE 2>&1
	if [ "$?" == "1" ];then
		cd $acme_root
		echo_date 证书申请失败，请检查插件配置、域名等是否正确！！ >> $LOGFILE
		echo_date 清理相关残留并关闭插件！！ >> $LOGFILE
		rm -rf /jffs/softcenter/acme/"$acme_domain" > /dev/null 2>&1
		rm -rf /jffs/softcenter/acme/*"$acme_domain" > /dev/null 2>&1
		rm -rf /jffs/softcenter/acme/http.header > /dev/null 2>&1
		dbus set acme_enable="0"
	else
		echo_date 证书申请成功！>> $LOGFILE
		echo_date 添加证书更新定时任务！
		add_cron
		echo_date 安装证书！ >> $LOGFILE
		echo_date 安装证书会重启路由器web服务，安装完成后需要重新登录路由器 >> $LOGFILE
		echo_date 安装中，，，请等待页面自动刷新！ >> $LOGFILE
		echo XU6J03M7 >> $LOGFILE
		install_cert
	fi
}

# start by init
case $ACTION in
start)
	if [ "$acme_enable" == "1" ];then
		# detect domain folder first
		cd $acme_root
		if [ -d "$acme_subdomain.$acme_domain" ] && [ -f "$acme_subdomain.$acme_domain/$acme_subdomain.$acme_domain.key" ] && [ -f "$acme_subdomain.$acme_domain/fullchain.cer" ];then
			logger "【Let's Encrypt】检测到Let's Encrypt证书！安装并添加证书更新定时任务！"
			echo "【Let's Encrypt】检测到Let's Encrypt证书！安装并添加证书更新定时任务！" > $LOGFILE
			add_cron
			install_cert
		else
			logger "【Let's Encrypt】$acme_subdomain.$acme_domain证书未生成或者生成的证书有问题，尝试重新申请！"
			echo "【Let's Encrypt】$acme_subdomain.$acme_domain证书未生成或者生成的证书有问题，尝试重新申请！" > $LOGFILE
			del_all_cert
			apply_now
		fi
	else
		logger "Let's Encrypt插件未开启，跳过！"
	fi
	;;
restart)
	echo "------------------------------ Let's Encrypt merlin addon by sadog -------------------------------" > $LOGFILE
	echo "" >> $LOGFILE
	[ ! -L "/jffs/softcenter/init.d/S99acme.sh" ] && ln -sf /jffs/softcenter/scripts/acme_config.sh /jffs/softcenter/init.d/S99acme.sh
	if [ "$acme_enable" == "1" ];then
		# detect domain folder and coresponding cert first
		cd $acme_root
		# 检测对应主域名证书是否申请过
		if [ -d "$acme_subdomain.$acme_domain" ] && [ -f "$acme_subdomain.$acme_domain/$acme_subdomain.$acme_domain.key" ] && [ -f "$acme_subdomain.$acme_domain/fullchain.cer" ];then
			# 申请过了，检测对应二级域名是否申请过了
			check_cert
			if [ "$acme_subdomain" == "$SUB" ];then
				# 对应你个二级域名申请过了，检测是否安装了
				check_md5
				if [ "$md5sum_cer_jffs"x = "$md5sum_cer_acme"x ] && [ "$md5sum_key_jffs"x = "$md5sum_key_acme"x ];then
					#安装了，检测定时任务
					echo_date 检测到已经为【$acme_subdomain.$acme_domain】申请了证书并且正确安装，跳过！>> $LOGFILE
					cronjob=`cru l | grep acme_renew`
					if [ -n "$cronjob" ];then
						#有定时任务
						echo_date 检测到【$acme_subdomain.$acme_domain】证书自动更新定时任务正常，跳过！>> $LOGFILE
					else
						#无定时任务
						echo_date 检测到【$acme_subdomain.$acme_domain】证书自动更新定时任务未添加！>> $LOGFILE
						echo_date 添加证书更新定时任务！>> $LOGFILE
						add_cron >> $LOGFILE
					fi
				else
					#申请过了，但是没有安装
					echo_date 检测到你之前生成【$acme_subdomain.$acme_domain】的证书，本次跳过申请，直接安装！ >> $LOGFILE
					echo_date 如果该证书已经过期，请本次提交完成后手动更新证书。 >> $LOGFILE
					echo_date 添加证书更新定时任务！>> $LOGFILE
					add_cron >> $LOGFILE
					echo_date 安装证书！ >> $LOGFILE
					echo_date 安装证书会重启路由器web服务，安装完成后需要重新登录路由器 >> $LOGFILE
					echo_date 安装中，，，请等待页面自动刷新！ >> $LOGFILE
					echo XU6J03M7 >> $LOGFILE
					install_cert
				fi
			else
				# 对应你个二级域名没申请过
				# 删除主域名文件夹并申请更新的
				echo_date 检测到你之前生成过该域名【$SUB.$acme_domain】证书，但是本次申请的二级域名不同！ >> $LOGFILE
				echo_date 删除原先生成的证书，重新申请新的证书！ >> $LOGFILE
				del_all_cert
				apply_now
			fi
		else
			#主域名文件夹不存在或者存在但是证书不齐全
			del_all_cert
			apply_now			
		fi
	else
		if [ -d "$acme_subdomain.$acme_domain" ] && [ -f "$acme_subdomain.$acme_domain/$acme_domain.key" ] && [ -f "$acme_subdomain.$acme_domain/fullchain.cer" ];then
			check_md5
			if [ "$md5sum_cer_jffs"x = "$md5sum_cer_acme"x ] && [ "$md5sum_key_jffs"x = "$md5sum_key_acme"x ];then
				echo_date 检测到你已经成功申请并安装证书，关闭插件仅仅会关闭证书的自动更新。>> $LOGFILE
				echo_date 关闭插件状态下仍然可以使用手动更新对证书进行更新，请注意你的证书的过期时间！>> $LOGFILE
			else
				echo_date 关闭插件 >> $LOGFILE
				del_cron
			fi
		else
			echo_date 关闭插件 >> $LOGFILE
			del_cron
		fi
	fi
	echo "" >> $LOGFILE
	echo "--------------------------------------------------------------------------------------------------" >> $LOGFILE
	echo XU6J03M6 >> $LOGFILE
	sleep 2
	echo "" > $LOGFILE
	;;
toolscript)
	#强制更新
	echo "------------------------------ Let's Encrypt merlin addon by sadog -------------------------------" > $LOGFILE
	echo_date 强制更新证书，即使证书未过期，请注意使用频率。>> $LOGFILE
	force_renew >> $LOGFILE
	echo "" >> $LOGFILE
	echo "--------------------------------------------------------------------------------------------------" >> $LOGFILE
	echo XU6J03M6 >> $LOGFILE
	sleep 2
	echo "" > $LOGFILE
	;;
clean)
	#删除证书
	echo "------------------------------ Let's Encrypt merlin addon by sadog -------------------------------" > $LOGFILE
	echo_date 删除所有本插件生成的证书...>> $LOGFILE
	echo_date 路由器上已经安装的证书...>> $LOGFILE
	del_all_cert
	echo_date 定时更新任务...>> $LOGFILE
	del_cron
	echo_date 关闭本插件！>> $LOGFILE
	dbus set acme_enable="0"
	echo "" >> $LOGFILE
	echo "--------------------------------------------------------------------------------------------------" >> $LOGFILE
	echo XU6J03M6 >> $LOGFILE
	sleep 2
	echo "" > $LOGFILE
	;;
esac
