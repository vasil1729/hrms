import json
import os

import frappe
from frappe.utils.install import complete_setup_wizard


def generate_api_keys():
    """Generate API key+secret for the admin user and write to shared volume."""
    email = os.environ.get("HRMS_ADMIN_EMAIL", "admin@example.com")
    if not frappe.db.exists("User", email):
        print("Admin user not found, skipping API key generation")
        return

    user = frappe.get_doc("User", email)
    api_key = frappe.generate_hash(length=20)
    api_secret = frappe.generate_hash(length=20)
    user.api_key = api_key
    user.api_secret = api_secret
    user.flags.ignore_permissions = True
    user.save(ignore_permissions=True)
    frappe.db.commit()

    keys_path = "/home/frappe/frappe-bench/sites/api_keys.json"
    with open(keys_path, "w") as f:
        json.dump({"api_key": api_key, "api_secret": api_secret}, f)
    print(f"Generated API keys for {email}")


def create_admin_user():
    """Create the initial admin user if not already present."""
    email = os.environ.get("HRMS_ADMIN_EMAIL", "admin@example.com")
    password = os.environ.get("HRMS_ADMIN_PASSWORD", "<replace-with-strong-password>")
    first_name = os.environ.get("HRMS_ADMIN_FIRST_NAME", "Admin")

    if frappe.db.exists("User", email):
        print(f"User {email} already exists, skipping creation")
        return

    user = frappe.new_doc("User")
    user.email = email
    user.first_name = first_name
    user.last_name = "Admin"
    user.new_password = password
    user.send_welcome_email = 0
    user.flags.ignore_permissions = True
    for role in ["System Manager", "HR Manager", "HR User", "Expense Approver", "Fleet Manager"]:
        user.append("roles", {"role": role})
    user.insert(ignore_permissions=True)
    frappe.db.commit()
    print(f"Created admin user: {email}")


def disable_self_signup():
    """Disable public self-signup to restrict access to allowed users only."""
    ss = frappe.get_single("System Settings")
    ss.allow_signup = 0
    ss.deny_self_signup = 1
    ss.flags.ignore_permissions = True
    ss.save(ignore_permissions=True)
    frappe.db.commit()
    print("Self-signup disabled")


def apply_site_config():
    """Apply overrides from site_config.json to the site config."""
    site_name = os.environ.get("SITE_NAME", "hrms.example.com")
    config_path = f"/home/frappe/frappe-bench/sites/{site_name}/site_config.json"
    overrides_path = "/home/frappe/site_config.json"

    if not os.path.exists(overrides_path):
        print("No site_config.json overrides found, skipping")
        return

    with open(overrides_path) as f:
        overrides = json.load(f)

    if os.path.exists(config_path):
        with open(config_path) as f:
            config = json.load(f)
    else:
        config = {}

    config.update({k: v for k, v in overrides.items() if not k.startswith("_")})

    with open(config_path, "w") as f:
        json.dump(config, f, indent=1)

    frappe.db.commit()
    print(f"Applied {len(overrides)} site config overrides")


def ensure_company_and_fiscal_year():
    """Create a default company and fiscal year if none exist."""
    companies = frappe.db.get_all("Company", limit=1)
    if not companies:
        print("No company found, creating default company...")
        company = frappe.new_doc("Company")
        company.company_name = "Personal"
        company.abbr = "Personal"
        company.country = "India"
        company.default_currency = "INR"
        company.enable_perpetual_inventory = 0
        company.flags.ignore_permissions = True
        company.insert(ignore_permissions=True)
        frappe.db.commit()
        print(f"Created company: {company.name}")
    else:
        company = frappe.get_doc("Company", companies[0].name)

    fys = frappe.db.get_all("Fiscal Year", limit=1)
    if not fys:
        print("No fiscal year found, creating FY 2026...")
        fy = frappe.new_doc("Fiscal Year")
        fy.year = "2026"
        fy.year_start_date = "2026-01-01"
        fy.year_end_date = "2026-12-31"
        fy.flags.ignore_permissions = True
        fy.insert(ignore_permissions=True)
        frappe.db.commit()
        print(f"Created fiscal year: {fy.name}")
    else:
        fy = frappe.get_doc("Fiscal Year", fys[0].name)

    gd = frappe.get_single("Global Defaults")
    if not gd.default_fiscal_year:
        gd.default_fiscal_year = fy.name
        gd.flags.ignore_permissions = True
        gd.save(ignore_permissions=True)
        frappe.db.commit()
        print(f"Set {fy.name} as global default fiscal year")


def ensure_system_manager_in_custom_perms():
    """Add System Manager role to all Custom DocPerm records if missing."""
    parents = frappe.db.get_all("Custom DocPerm", pluck="parent", distinct=True)
    count = 0
    for parent in parents:
        existing = frappe.db.get_value("Custom DocPerm", {"parent": parent, "role": "System Manager"})
        if not existing:
            perm = frappe.new_doc("Custom DocPerm")
            perm.parent = parent
            perm.parenttype = "DocType"
            perm.parentfield = "permissions"
            perm.role = "System Manager"
            perm.select = 1
            perm.read = 1
            perm.write = 1
            perm.create = 1
            perm.delete = 1
            perm.submit = 1
            perm.amend = 1
            perm.cancel = 1
            perm.report = 1
            perm.import_perms = 1
            perm.export_perms = 1
            perm.share = 1
            perm.print_perms = 1
            perm.email = 1
            perm.flags.ignore_permissions = True
            perm.insert(ignore_permissions=True)
            count += 1
    if count:
        frappe.db.commit()
        print(f"Added System Manager to {count} Custom DocPerm doctypes")


def run():
    print("=" * 60)
    print("  Frappe HRMS Post-Setup Configuration")
    print("=" * 60)

    complete_setup_wizard()
    ensure_company_and_fiscal_year()

    create_admin_user()
    generate_api_keys()
    disable_self_signup()
    apply_site_config()
    ensure_system_manager_in_custom_perms()

    print("=" * 60)
    print("  Configuration complete")
    print("=" * 60)


if __name__ == "__main__":
    run()
