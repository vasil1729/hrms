// Copyright (c) 2015, Frappe Technologies Pvt. Ltd. and Contributors
// License: GNU General Public License v3. See license.txt

// For license information, please see license.txt

// for communication
cur_frm.email_field = "email_id";

frappe.ui.form.on("Job Applicant", {
	refresh: function (frm) {
		frm.set_query("job_title", function () {
			return {
				filters: {
					status: "Open",
				},
			};
		});
		frm.events.create_custom_buttons(frm);
		frm.events.make_dashboard(frm);
		frappe.boot.desk_settings.form_navigation_buttons = 1;
	},

	create_custom_buttons: function (frm) {
		if (!frm.doc.__islocal) {
			if (frm.doc.status == "Open") {
				frm.add_custom_button(__("Shortlist"), () => {
					frm.set_value("status", "Shortlisted");
					frm.save();
					frm.refresh();
				});
				frm.add_custom_button(__("Reject"), () => {
					frm.set_value("status", "Rejected");
					frm.save();
					frm.refresh();
				});
			}
			if (frm.doc.status !== "Rejected" && frm.doc.status !== "Accepted") {
				frm.add_custom_button(__("Create Interview"), function () {
					frm.events.create_dialog(frm);
				});
			}
		}

		if (!frm.doc.__islocal && frm.doc.status == "Accepted") {
			if (frm.doc.__onload && frm.doc.__onload.job_offer) {
				$('[data-doctype="Employee Onboarding"]').find("button").show();
				$('[data-doctype="Job Offer"]').find("button").hide();
				frm.add_custom_button(__("View Job Offer"), function () {
					frappe.set_route("Form", "Job Offer", frm.doc.__onload.job_offer);
				});
			} else {
				$('[data-doctype="Employee Onboarding"]').find("button").hide();
				$('[data-doctype="Job Offer"]').find("button").show();
				frm.add_custom_button(__("Create Job Offer"), function () {
					frappe.route_options = {
						job_applicant: frm.doc.name,
						applicant_name: frm.doc.applicant_name,
						designation: frm.doc.job_opening || frm.doc.designation,
					};
					frappe.new_doc("Job Offer");
				});
			}
		}
	},

	make_dashboard: function (frm) {
		frappe.call({
			method: "hrms.hr.doctype.job_applicant.job_applicant.get_interview_details",
			args: {
				job_applicant: frm.doc.name,
			},
			callback: function (r) {
				if (r.message) {
					$("div").remove(".form-dashboard-section.custom");
					frm.dashboard.add_section(
						frappe.render_template("job_applicant_dashboard", {
							data: r.message.interviews,
							number_of_stars: r.message.stars,
						}),
						__("Interview Summary"),
					);
				}
			},
		});
	},

	create_dialog: function (frm) {
		let d = new frappe.ui.Dialog({
			title: __("Enter Interview Type"),
			fields: [
				{
					label: "Interview Type",
					fieldname: "interview_type",
					fieldtype: "Link",
					options: "Interview Type",
					get_query: function () {
						return {
							filters: [["designation", "=", frm.doc.designation]],
						};
					},
				},
			],
			primary_action_label: __("Create Interview"),
			primary_action(values) {
				frm.events.create_interview(frm, values);
				d.hide();
			},
		});
		d.show();
	},

	create_interview: function (frm, values) {
		frappe.call({
			method: "hrms.hr.doctype.job_applicant.job_applicant.create_interview",
			args: {
				job_applicant: frm.doc.name,
				interview_type: values.interview_type,
			},
			callback: function (r) {
				var doclist = frappe.model.sync(r.message);
				frappe.set_route("Form", doclist[0].doctype, doclist[0].name);
			},
		});
	},
});
