ARG ERPNext_VERSION=v15.41.0

FROM frappe/erpnext:${ERPNext_VERSION}

LABEL maintainer="Dev <admin@example.com>"
LABEL description="Frappe ERPNext with HRMS app"
LABEL version="1.0.0"

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git \
       nodejs \
       npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home/frappe/frappe-bench
RUN su frappe -c "bench get-app --branch v15.0.0 hrms https://github.com/frappe/hrms"

# Patch: HRMS India regional setup creates Gratuity Rule without ignore_permissions
# Remove when upstream HRMS fixes the bug
RUN sed -i 's/rule.flags.ignore_mandatory = True/rule.flags.ignore_mandatory = True\n\trule.flags.ignore_permissions = True/' \
    /home/frappe/frappe-bench/apps/hrms/hrms/regional/india/setup.py

USER frappe
