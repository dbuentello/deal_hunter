require 'capybara'
require 'capybara/poltergeist'

class GetHomeListingsService
  TD_COLUMN    = "td".freeze
  BLANK_SPACE  = "".freeze
  WHITE_SPACE  = " ".freeze

  def self.call
    set_up_crawler
    @result = []

    begin
      login
      go_to_metro_list
      @result = crawl_data
      log_off
    rescue Capybara::ElementNotFound => error
      Rollbar.error(error)
    ensure
      close_crawler
    end

    @result
  end

  def self.login
    @session.visit("https://connect.mlslistings.com/SAML/CSAuthnRequestIssuer.ashx?RelayUrl=http://pro.mlslistings.com/")
    @session.execute_script("$('#j_username').val('01972404')")
    @session.execute_script("$('#password').val('mortgage123')")
    @session.execute_script("$('#j_password').val('mortgage123')")
    @session.execute_script("$('#login').trigger('click')")
    sleep(20)
  end

  def self.go_to_metro_list
    login
    @session.click_link("MainContent_OtherMLS1_rpOtherApplications_SACM_3")
    @session.visit("http://qtrosso.rapmls.com/sp/startSSO.ping?PartnerIdpId=MLSListingsIdentityProvider&TargetResource=http://login.rapmls.com/SACM/','SACM'")
    @session.execute_script("$('#btnContinue').trigger('click')")
    sleep(5)
  end

  def self.crawl_data
    @session_id = @session.current_url.split("&SID=").last
    count = 0
    data = Nokogiri::HTML.parse(@session.html)

    while data.css(".subject-list-grid").empty? && count < 5
      @session.visit("http://search.metrolist.net/ListingGridDisplay.aspx?hidMLS=SACM&GRID=137130&PTYPE=RESI&SRC=HS&SRID=218452559&PRINT=0&SAS=0&ARCH=0&HIDD=0&REMO=0&SNAME=Sacramento+County&CARTID=&SPLISTINGRID=0&STYPE=HS&SID=#{@session_id}")
      sleep(4)
      data = Nokogiri::HTML.parse(@session.html)
      count += 1
    end

    return [] if data.css(".subject-list-grid").empty?

    data = Nokogiri::HTML.parse(@session.html)
    result = []
    table = data.css(".subject-list-grid")
    table.css("tr").each do |tr|
      next if tr.css(TD_COLUMN).size < 2

      listing_id = tr.css(TD_COLUMN)[1].text
      home_type = tr.css(TD_COLUMN)[2].text.strip
      home_status = tr.css(TD_COLUMN)[3].text.strip.freeze
      address = tr.css(TD_COLUMN)[4].text
      city = tr.css(TD_COLUMN)[5].text.freeze
      zipcode = tr.css(TD_COLUMN)[6].text
      price = tr.css(TD_COLUMN)[7].text.gsub(/[^0-9\.]/, BLANK_SPACE).to_f
      bedroom = tr.css(TD_COLUMN)[8].text.to_i
      bathroom = tr.css(TD_COLUMN)[9].text
      dom_cdom = tr.css(TD_COLUMN)[10].text
      remark = tr.css(TD_COLUMN)[11].text.strip
      full_name = tr.css(TD_COLUMN)[12].text.strip
      first_name = full_name.split(WHITE_SPACE).first
      last_name = full_name.split(WHITE_SPACE).last
      agent_email = tr.css(TD_COLUMN)[13].text
      agent_phone = "1".freeze + tr.css(TD_COLUMN)[14].text.gsub("-".freeze, BLANK_SPACE)
      office_name = tr.css(TD_COLUMN)[15].text
      sq_ft = tr.css(TD_COLUMN)[16].text.to_f

      result << {
        listing_id: listing_id, price: price, address: address,
        city: city, zipcode: zipcode,
        home_type: home_type, home_status: home_status,
        bedroom: bedroom, bathroom: bathroom, dom_cdom: dom_cdom,
        remark: remark, sq_ft: sq_ft,
        agent: {
          full_name: full_name,
          first_name: first_name,
          last_name: last_name,
          phone: agent_phone,
          email: agent_email,
          office_name: office_name
        }
      }
    end
    result
  end

  def self.set_up_crawler
    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app, {
        js_errors: false, timeout: 60, phantomjs_options: ["--ignore-ssl-errors=yes", "--ssl-protocol=any"]
      })
    end
    Capybara.default_max_wait_time = 30
    @session = Capybara::Session.new(:poltergeist)
    @session.driver.headers = { "User-Agent" => "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36" }
    # @session = Capybara::Session.new(:selenium)
  end

  def self.log_off
    @session.visit("http://login.metrolist.net/Menu.aspx?hidMLS=SACM&SID=#{@session_id}")
    @session.find("#LogOff1_btnLogOff").click
    sleep(5)
  end

  def self.close_crawler
    @session.driver.quit
  end
end
