require 'spec_helper'

describe "Admin::Users", feature: true  do
  before { login_as :admin }

  describe "GET /admin/users" do
    before do
      visit admin_users_path
    end

    it "should be ok" do
      expect(current_path).to eq(admin_users_path)
    end

    it "should have users list" do
      expect(page).to have_content(@user.email)
      expect(page).to have_content(@user.name)
    end

    describe 'Two-factor Authentication filters' do
      it 'counts users who have enabled 2FA' do
        create(:user, two_factor_enabled: true)

        visit admin_users_path

        page.within('.filter-two-factor-enabled small') do
          expect(page).to have_content('1')
        end
      end

      it 'filters by users who have enabled 2FA' do
        user = create(:user, two_factor_enabled: true)

        visit admin_users_path
        click_link '2FA Enabled'

        expect(page).to have_content(user.email)
      end

      it 'counts users who have not enabled 2FA' do
        create(:user, two_factor_enabled: false)

        visit admin_users_path

        page.within('.filter-two-factor-disabled small') do
          expect(page).to have_content('2') # Including admin
        end
      end

      it 'filters by users who have not enabled 2FA' do
        user = create(:user, two_factor_enabled: false)

        visit admin_users_path
        click_link '2FA Disabled'

        expect(page).to have_content(user.email)
      end
    end
  end

  describe "GET /admin/users/new" do
    before do
      visit new_admin_user_path
      fill_in "user_name", with: "Big Bang"
      fill_in "user_username", with: "bang"
      fill_in "user_email", with: "bigbang@mail.com"
    end

    it "should create new user" do
      expect { click_button "Create user" }.to change {User.count}.by(1)
    end

    it "should apply defaults to user" do
      click_button "Create user"
      user = User.find_by(username: 'bang')
      expect(user.projects_limit).
        to eq(Gitlab.config.gitlab.default_projects_limit)
      expect(user.can_create_group).
        to eq(Gitlab.config.gitlab.default_can_create_group)
    end

    it "should create user with valid data" do
      click_button "Create user"
      user = User.find_by(username: 'bang')
      expect(user.name).to eq('Big Bang')
      expect(user.email).to eq('bigbang@mail.com')
    end

    it "should call send mail" do
      expect_any_instance_of(NotificationService).to receive(:new_user)

      click_button "Create user"
    end

    it "should send valid email to user with email & password" do
      perform_enqueued_jobs do
        click_button "Create user"
      end

      user = User.find_by(username: 'bang')
      email = ActionMailer::Base.deliveries.last
      expect(email.subject).to have_content('Account was created')
      expect(email.text_part.body).to have_content(user.email)
      expect(email.text_part.body).to have_content('password')
    end
  end

  describe "GET /admin/users/:id" do
    it "should have user info" do
      visit admin_users_path
      click_link @user.name

      expect(page).to have_content(@user.email)
      expect(page).to have_content(@user.name)
    end

    describe 'Impersonation' do
      let(:another_user) { create(:user) }
      before { visit admin_user_path(another_user) }

      context 'before impersonating' do
        it 'shows impersonate button for other users' do
          expect(page).to have_content('Impersonate')
        end

        it 'should not show impersonate button for admin itself' do
          visit admin_user_path(@user)

          expect(page).not_to have_content('Impersonate')
        end

        it 'should not show impersonate button for blocked user' do
          another_user.block

          visit admin_user_path(another_user)

          expect(page).not_to have_content('Impersonate')

          another_user.activate
        end
      end

      context 'when impersonating' do
        before { click_link 'Impersonate' }

        it 'logs in as the user when impersonate is clicked' do
          page.within '.sidebar-user .username' do
            expect(page).to have_content(another_user.username)
          end
        end

        it 'sees impersonation log out icon' do
          icon = first('.fa.fa-user-secret')

          expect(icon).not_to eql nil
        end

        it 'can log out of impersonated user back to original user' do
          find(:css, 'li.impersonation a').click

          page.within '.sidebar-user .username' do
            expect(page).to have_content(@user.username)
          end
        end

        it 'is redirected back to the impersonated users page in the admin after stopping' do
          find(:css, 'li.impersonation a').click

          expect(current_path).to eql "/admin/users/#{another_user.username}"
        end
      end
    end

    describe 'Two-factor Authentication status' do
      it 'shows when enabled' do
        @user.update_attribute(:two_factor_enabled, true)

        visit admin_user_path(@user)

        expect_two_factor_status('Enabled')
      end

      it 'shows when disabled' do
        visit admin_user_path(@user)

        expect_two_factor_status('Disabled')
      end

      def expect_two_factor_status(status)
        page.within('.two-factor-status') do
          expect(page).to have_content(status)
        end
      end
    end
  end

  describe "GET /admin/users/:id/edit" do
    before do
      @simple_user = create(:user)
      visit admin_users_path
      click_link "edit_user_#{@simple_user.id}"
    end

    it "should have user edit page" do
      expect(page).to have_content('Name')
      expect(page).to have_content('Password')
    end

    describe "Update user" do
      before do
        fill_in "user_name", with: "Big Bang"
        fill_in "user_email", with: "bigbang@mail.com"
        fill_in "user_password", with: "AValidPassword1"
        fill_in "user_password_confirmation", with: "AValidPassword1"
        check "user_admin"
        click_button "Save changes"
      end

      it "should show page with  new data" do
        expect(page).to have_content('bigbang@mail.com')
        expect(page).to have_content('Big Bang')
      end

      it "should change user entry" do
        @simple_user.reload
        expect(@simple_user.name).to eq('Big Bang')
        expect(@simple_user.is_admin?).to be_truthy
        expect(@simple_user.password_expires_at).to be <= Time.now
      end
    end
  end
end
