# Kind of crazy Capybara integration test showing it works with simple_form and
# cocoon.
RSpec.describe "form with simple_form and cocoon", type: :feature, js: true do

  around do |example|
    # We like having config.warnings=true but for this suite only it generates
    # a bunch, we'll turn it off here only.
    original = $VERBOSE
    $VERBOSE = nil

    example.run

    $VERBOSE = original
  end

  describe "new document" do
    before do
      visit new_document_path
    end

    describe "with errors" do
      it "reports validation errors" do
        click_on "add Person role"
        click_on "add Person"
        click_on "Create Document"

        expect(page).to have_current_path(documents_path)
        expect(page).to have_content "Person roles is invalid"
        within(".document_person_roles_people_given_name") do
          expect(page).to have_content "can't be blank"
        end
      end
    end

    describe "with good data" do
      let(:doc_title) { "A Document" }
      let(:role) { "author" }
      let(:given) { "Jim" }
      let(:family) { "Smith-Jones" }
      let(:birth_year) { "2017" }
      let(:birth_month) { "May" }
      let(:birth_day) { "1" }

      it "submits data" do
        visit new_document_path

        fill_in "Title", with: doc_title
        click_on "add Person role"
        fill_in "Role", with: role


        click_on "add Person"
        fill_in "Given name", with: given
        fill_in "Family name", with: family
        # oh boy the way rails/simple_form/cocoon does this makes
        # it hard. we help a bit with a custom birth-date class we added
        # in simple form args.
        within(".birth-date") do
          find(:xpath, "//select[1]").find(:xpath, "option[text()='#{birth_year}']").select_option
          find(:xpath, "//select[2]").find(:xpath, "option[text()='#{birth_month}']").select_option
          find(:xpath, "//select[3]").find(:xpath, "option[text()='#{birth_day}']").select_option
        end

        click_on "Create Document"

        expect(page).to have_text("Document was successfully created.")

        # now make sure it really saved
        doc = Document.last
        expect(doc).to be_present
        expect(doc.title).to eq doc_title

        expect(doc.person_roles.length).to eq 1
        person_role = doc.person_roles.first
        expect(person_role.role).to eq role

        expect(person_role.people.length).to eq 1
        person = person_role.people.first
        expect(person.given_name).to eq given
        expect(person.family_name).to eq family

        expect(person.birth_date).to be_present
        expect(person.birth_date.year).to eq birth_year.to_i
        expect(person.birth_date.month).to eq Date::ABBR_MONTHNAMES.index(birth_month)
        expect(person.birth_date.day).to eq birth_day.to_i
      end
    end
  end
end
