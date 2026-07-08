import json
import os

import frappe
from frappe.utils.install import complete_setup_wizard


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


def run():
    print("=" * 60)
    print("  Frappe HRMS Post-Setup Configuration")
    print("=" * 60)

    complete_setup_wizard()

    create_admin_user()
    disable_self_signup()
    apply_site_config()

    print("=" * 60)
    print("  Configuration complete")
    print("=" * 60)


if __name__ == "__main__":
    run()
