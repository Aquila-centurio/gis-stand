FROM gis-base

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server openssh-client sshpass \
        sssd-ad sssd-tools libnss-sss libpam-sss adcli krb5-user \
        libpam-pwquality cracklib-runtime \
        acl aide clamav auditd rsyslog \
    && rm -rf /var/lib/apt/lists/*

# Аналоги Secret Net (этап 05, часть Б): AIDE (контроль целостности), ClamAV (антивирус,
# локальная сигнатура EICAR вместо официальной базы — стенд без интернета), rsyslog (журнал входов).
COPY aide-gis.conf /etc/aide/aide-gis.conf
COPY gis-eicar.ndb /var/lib/clamav/gis-eicar.ndb
# imklog читает журнал ядра, в контейнере нет доступа к /proc/kmsg.
RUN sed -i 's/^module(load="imklog"/#&/' /etc/rsyslog.conf

# Клиент домена: Kerberos, SSSD, PAM (faillock + pwquality + создание домашних каталогов).
COPY krb5.conf /etc/krb5.conf
COPY sssd.conf /etc/sssd/sssd.conf
COPY faillock.conf /etc/security/faillock.conf
COPY pwquality.conf /etc/security/pwquality.conf
COPY pam/common-auth pam/common-account pam/common-password pam/common-session /etc/pam.d/
RUN chmod 600 /etc/sssd/sssd.conf \
    # pam_loginuid в контейнере без CAP_AUDIT_CONTROL не может записать loginuid и рвёт сессию sshd.
    && sed -i 's/^session\s\+required\s\+pam_loginuid.so/session    optional     pam_loginuid.so/' /etc/pam.d/sshd

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
